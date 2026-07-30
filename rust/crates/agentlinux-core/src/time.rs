//! Epoch → ISO-8601 formatting for the sentinel timestamps.
//!
//! Pure arithmetic (a proleptic-Gregorian civil-from-days), so it belongs in the
//! core: the bin owns the clock read, this owns the conversion.
//!
//! It lived in THREE byte-identical copies (`cmd/{install,upgrade,adopt}.rs`)
//! with only the `adopt` copy tested, and by two assertions. That is exactly the
//! integer arithmetic — the 719_468/146_097 era constants, the `mp < 10` month
//! rotation — where an off-by-one appears at a leap day or a century boundary
//! and not at the epoch, so a mutation in the other two copies was undetectable.

/// Format unix seconds as `YYYY-MM-DDTHH:MM:SSZ` (proleptic Gregorian, UTC) —
/// matching JavaScript's `new Date().toISOString()` at second resolution.
#[must_use]
pub fn format_epoch_utc(secs: u64) -> String {
    let days = secs / 86_400;
    let rem = secs % 86_400;
    let (hh, mm, ss) = (rem / 3600, (rem % 3600) / 60, rem % 60);
    let z = days as i64 + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u64;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = if m <= 2 { y + 1 } else { y };
    format!("{year:04}-{m:02}-{d:02}T{hh:02}:{mm:02}:{ss:02}Z")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_epoch_itself() {
        assert_eq!(format_epoch_utc(0), "1970-01-01T00:00:00Z");
    }

    #[test]
    fn known_instants() {
        assert_eq!(format_epoch_utc(1_700_000_000), "2023-11-14T22:13:20Z");
        assert_eq!(format_epoch_utc(946_684_800), "2000-01-01T00:00:00Z");
        assert_eq!(format_epoch_utc(1_735_689_599), "2024-12-31T23:59:59Z");
    }

    #[test]
    fn leap_days_and_the_days_around_them() {
        // 2024 is a leap year: Feb 29 exists.
        assert_eq!(format_epoch_utc(1_709_164_800), "2024-02-29T00:00:00Z");
        assert_eq!(format_epoch_utc(1_709_164_800 - 1), "2024-02-28T23:59:59Z");
        assert_eq!(
            format_epoch_utc(1_709_164_800 + 86_400),
            "2024-03-01T00:00:00Z"
        );
    }

    #[test]
    fn the_century_leap_rule() {
        // 2000 IS a leap year (divisible by 400); 1900 and 2100 are NOT. This is
        // the rule the `yoe` term encodes, and the one an off-by-one in the era
        // constants breaks — far from the epoch, so no hand-picked "now" catches it.
        assert_eq!(format_epoch_utc(951_782_400), "2000-02-29T00:00:00Z");
        assert_eq!(format_epoch_utc(4_107_542_400), "2100-03-01T00:00:00Z");
        assert_eq!(
            format_epoch_utc(4_107_542_400 - 86_400),
            "2100-02-28T00:00:00Z"
        );
    }

    #[test]
    fn every_component_is_zero_padded_to_a_fixed_width() {
        // The sentinel is compared as a STRING in places, so the width is part
        // of the contract.
        let s = format_epoch_utc(1_041_379_265);
        assert_eq!(s.len(), 20);
        assert_eq!(s, "2003-01-01T00:01:05Z");
    }
}

#[cfg(test)]
mod proptests {
    //! Verified against an INDEPENDENT inverse: the test parses the formatted
    //! string back to seconds by accumulating years and months with its own leap
    //! rule, never by re-calling the function under test. A shared-algorithm
    //! round-trip would agree with itself on any off-by-one.
    use super::*;
    use proptest::prelude::*;

    /// Days in `month` (1-12) of `year`, by the plain Gregorian rule.
    fn days_in_month(year: i64, month: u64) -> u64 {
        match month {
            1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
            4 | 6 | 9 | 11 => 30,
            2 if (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 => 29,
            2 => 28,
            _ => unreachable!("month out of range: {month}"),
        }
    }

    /// `YYYY-MM-DDTHH:MM:SSZ` → unix seconds, counted forward from 1970 one year
    /// and one month at a time.
    fn parse_iso8601(s: &str) -> u64 {
        let year: i64 = s[0..4].parse().unwrap();
        let month: u64 = s[5..7].parse().unwrap();
        let day: u64 = s[8..10].parse().unwrap();
        let hh: u64 = s[11..13].parse().unwrap();
        let mm: u64 = s[14..16].parse().unwrap();
        let ss: u64 = s[17..19].parse().unwrap();
        assert_eq!(&s[19..20], "Z");

        let mut days = 0u64;
        for y in 1970..year {
            days += if (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 {
                366
            } else {
                365
            };
        }
        for m in 1..month {
            days += days_in_month(year, m);
        }
        days += day - 1;
        days * 86_400 + hh * 3600 + mm * 60 + ss
    }

    proptest! {
        // Round-trip over 1970-2100 — the whole range a sentinel can carry.
        #[test]
        fn format_then_parse_is_the_identity(secs in 0u64..4_133_980_800) {
            let formatted = format_epoch_utc(secs);
            prop_assert_eq!(parse_iso8601(&formatted), secs, "formatted={}", formatted);
        }

        // Every field is in range and fixed-width, whatever the instant.
        #[test]
        fn the_shape_is_always_well_formed(secs in 0u64..4_133_980_800) {
            let s = format_epoch_utc(secs);
            prop_assert_eq!(s.len(), 20, "s={}", s);
            let month: u64 = s[5..7].parse().unwrap();
            let day: u64 = s[8..10].parse().unwrap();
            let year: i64 = s[0..4].parse().unwrap();
            prop_assert!((1..=12).contains(&month), "s={}", s);
            prop_assert!(day >= 1 && day <= days_in_month(year, month), "s={}", s);
            prop_assert!(s[11..13].parse::<u64>().unwrap() < 24, "s={}", s);
            prop_assert!(s[14..16].parse::<u64>().unwrap() < 60, "s={}", s);
            prop_assert!(s[17..19].parse::<u64>().unwrap() < 60, "s={}", s);
        }

        // Chronological order IS lexicographic order — the property that lets a
        // sentinel timestamp be compared as a plain string.
        #[test]
        fn later_instants_sort_later_as_strings(
            a in 0u64..4_133_980_800,
            b in 0u64..4_133_980_800,
        ) {
            let (fa, fb) = (format_epoch_utc(a), format_epoch_utc(b));
            prop_assert_eq!(a.cmp(&b), fa.cmp(&fb), "a={} b={}", fa, fb);
        }
    }
}
