//! distro.rs — supported-distro gate + family bucket (PROV-03).
//!
//! Byte-for-byte port of `plugin/lib/distro_detect.sh::detect_distro`. The
//! installer accepts Ubuntu 22.04 / 24.04 / 26.04 (`Family::Debian`) and
//! AlmaLinux 9.x (`Family::Rhel`); everything else is refused. `ID` is matched
//! EXACTLY (never the looser os-release similarity field) so Rocky/RHEL/CentOS/
//! Fedora and AlmaLinux 8/10 stay explicitly refused — no silent admission of an
//! untested family.
//!
//! Two bats seams the Bash lib exposes are preserved so the Wave-5 shim-or-
//! rewrite decision has a green Rust equivalent to point at:
//!   - `AGENTLINUX_OS_RELEASE_PATH` overrides the os-release path (the caller
//!     passes the already-resolved path here; `detect_distro_from_env` reads the
//!     env for the production default `/etc/os-release`).
//!   - `AGENTLINUX_SKIP_DISTRO_CHECK=1` bypasses validation, seeding the family
//!     from ID (almalinux→Rhel else Debian) and version `"unchecked"`.
//!
//! `dead_code` allowed at module scope: the public surface is consumed by the
//! Wave-1..4 provisioner steps; the `#[cfg(test)]` module exercises every path
//! now.
#![allow(dead_code)]

use std::fs;
use std::path::{Path, PathBuf};

/// The single fork point every later provisioner layer branches on — the
/// os-release ID bucketed to a package-manager family.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Family {
    /// apt / dpkg — Ubuntu.
    Debian,
    /// dnf / rpm — AlmaLinux 9.x.
    Rhel,
}

/// Refusal reasons, mirroring the Bash `log_error … ; return 1` cases so the
/// caller can decide whether to `|| exit 1`.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum DistroError {
    #[error("cannot read {0}; unsupported system")]
    Unreadable(String),
    #[error("unsupported ubuntu version: {0} (required: 22.04, 24.04 or 26.04)")]
    UnsupportedUbuntu(String),
    #[error("unsupported almalinux version: {0} (required: 9.x)")]
    UnsupportedAlma(String),
    #[error("unsupported distro: ID={0} (required: ubuntu | almalinux)")]
    UnsupportedDistro(String),
}

/// Detected distro: the family bucket + the raw os-release `VERSION_ID`
/// (e.g. "22.04", "9.4", or "unchecked" under the skip seam).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Distro {
    pub family: Family,
    pub version: String,
}

/// Parse the `key=value` shape os-release uses: strip surrounding double OR
/// single quotes from the value (os-release permits both). Returns the FIRST
/// occurrence of `key` (matching a `. os-release` source where the last
/// assignment would win — but ID/VERSION_ID appear once in practice; we take the
/// last to mirror shell sourcing exactly).
fn os_release_value(contents: &str, key: &str) -> Option<String> {
    let mut found = None;
    for line in contents.lines() {
        let line = line.trim();
        if line.starts_with('#') {
            continue;
        }
        if let Some(rest) = line.strip_prefix(key).and_then(|r| r.strip_prefix('=')) {
            let v = rest.trim();
            let v = v
                .strip_prefix('"')
                .and_then(|s| s.strip_suffix('"'))
                .or_else(|| v.strip_prefix('\'').and_then(|s| s.strip_suffix('\'')))
                .unwrap_or(v);
            // Shell sourcing: a later assignment overrides an earlier one.
            found = Some(v.to_string());
        }
    }
    found
}

/// Read the `AGENTLINUX_SKIP_DISTRO_CHECK` / `AGENTLINUX_DISTRO_FAMILY` env seams
/// (a struct so tests can drive them without touching the process env). Mirrors
/// the Bash `${AGENTLINUX_SKIP_DISTRO_CHECK:-0}` / explicit-family-override read.
#[derive(Debug, Default, Clone)]
pub struct DetectEnv {
    /// `AGENTLINUX_SKIP_DISTRO_CHECK` == "1".
    pub skip_check: bool,
    /// An explicit `AGENTLINUX_DISTRO_FAMILY` override ("debian"/"rhel"), if set.
    pub family_override: Option<String>,
}

impl DetectEnv {
    /// Read the seams from the real process environment (the production path).
    fn from_process_env() -> Self {
        Self {
            skip_check: std::env::var("AGENTLINUX_SKIP_DISTRO_CHECK").as_deref() == Ok("1"),
            family_override: std::env::var("AGENTLINUX_DISTRO_FAMILY")
                .ok()
                .filter(|s| !s.is_empty()),
        }
    }
}

/// Resolve the os-release path the production caller reads:
/// `$AGENTLINUX_OS_RELEASE_PATH` else `/etc/os-release` (the Bash default).
pub fn os_release_path_from_env() -> PathBuf {
    std::env::var("AGENTLINUX_OS_RELEASE_PATH")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/etc/os-release"))
}

/// Production entry point: resolve the os-release path + env seams from the
/// process environment, then delegate to the pure `detect_distro`.
pub fn detect_distro_from_env() -> Result<Distro, DistroError> {
    detect_distro(&os_release_path_from_env(), &DetectEnv::from_process_env())
}

/// `detect_distro` — read `os_release_path`, accept ubuntu 22.04|24.04|26.04
/// (Debian) and almalinux 9.x (Rhel), refuse everything else.
///
/// Honors the two bats seams via `env`:
///   - `skip_check`: bypass validation, seed family from the file's ID
///     (almalinux→Rhel else Debian) or an explicit `family_override`, version
///     `"unchecked"`.
///   - `family_override`: only consulted under `skip_check` (matches the Bash
///     `if [[ -z "${AGENTLINUX_DISTRO_FAMILY:-}" ]]` seed logic).
pub fn detect_distro(os_release_path: &Path, env: &DetectEnv) -> Result<Distro, DistroError> {
    // Read the file up front (may be absent under the skip seam, which is fine).
    let contents = fs::read_to_string(os_release_path).ok();

    if env.skip_check {
        // Explicit override wins; else read ID from the file if present; else
        // default debian (mirrors distro_detect.sh:53-63).
        let family = if let Some(f) = env.family_override.as_deref() {
            match f {
                "rhel" => Family::Rhel,
                _ => Family::Debian,
            }
        } else {
            let seed_id = contents
                .as_deref()
                .and_then(|c| os_release_value(c, "ID"))
                .unwrap_or_default();
            match seed_id.as_str() {
                "almalinux" => Family::Rhel,
                _ => Family::Debian,
            }
        };
        return Ok(Distro {
            family,
            version: "unchecked".to_string(),
        });
    }

    // Non-skip path: the file MUST be readable.
    let contents =
        contents.ok_or_else(|| DistroError::Unreadable(os_release_path.display().to_string()))?;

    let id = os_release_value(&contents, "ID").unwrap_or_default();
    let version_id = os_release_value(&contents, "VERSION_ID").unwrap_or_default();

    // Match ID EXACTLY — never the similarity field.
    match id.as_str() {
        "ubuntu" => match version_id.as_str() {
            "22.04" | "24.04" | "26.04" => Ok(Distro {
                family: Family::Debian,
                version: version_id,
            }),
            other => Err(DistroError::UnsupportedUbuntu(if other.is_empty() {
                "unset".to_string()
            } else {
                other.to_string()
            })),
        },
        "almalinux" => {
            // 9 | 9.* → rhel.
            if version_id == "9" || version_id.starts_with("9.") {
                Ok(Distro {
                    family: Family::Rhel,
                    version: version_id,
                })
            } else {
                Err(DistroError::UnsupportedAlma(if version_id.is_empty() {
                    "unset".to_string()
                } else {
                    version_id
                }))
            }
        }
        other => Err(DistroError::UnsupportedDistro(if other.is_empty() {
            "unset".to_string()
        } else {
            other.to_string()
        })),
    }
}

#[cfg(test)]
mod distro_tests {
    use super::*;
    use std::io::Write;
    use tempfile::TempDir;

    fn write_os_release(dir: &TempDir, contents: &str) -> PathBuf {
        let p = dir.path().join("os-release");
        let mut f = fs::File::create(&p).unwrap();
        f.write_all(contents.as_bytes()).unwrap();
        p
    }

    fn no_seams() -> DetectEnv {
        DetectEnv::default()
    }

    #[test]
    fn accepts_ubuntu_2404() {
        let d = TempDir::new().unwrap();
        let p = write_os_release(&d, "ID=ubuntu\nVERSION_ID=\"24.04\"\n");
        assert_eq!(
            detect_distro(&p, &no_seams()).unwrap(),
            Distro {
                family: Family::Debian,
                version: "24.04".into()
            }
        );
    }

    #[test]
    fn accepts_ubuntu_2204_and_2604() {
        let d = TempDir::new().unwrap();
        for v in ["22.04", "26.04"] {
            let p = write_os_release(&d, &format!("ID=ubuntu\nVERSION_ID={v}\n"));
            assert_eq!(
                detect_distro(&p, &no_seams()).unwrap().family,
                Family::Debian
            );
        }
    }

    #[test]
    fn accepts_almalinux_9x() {
        let d = TempDir::new().unwrap();
        let p = write_os_release(&d, "ID=\"almalinux\"\nVERSION_ID=\"9.4\"\n");
        assert_eq!(
            detect_distro(&p, &no_seams()).unwrap(),
            Distro {
                family: Family::Rhel,
                version: "9.4".into()
            }
        );
    }

    #[test]
    fn accepts_almalinux_bare_9() {
        let d = TempDir::new().unwrap();
        let p = write_os_release(&d, "ID=almalinux\nVERSION_ID=9\n");
        assert_eq!(detect_distro(&p, &no_seams()).unwrap().family, Family::Rhel);
    }

    #[test]
    fn rejects_unsupported_ubuntu_version() {
        let d = TempDir::new().unwrap();
        let p = write_os_release(&d, "ID=ubuntu\nVERSION_ID=20.04\n");
        assert_eq!(
            detect_distro(&p, &no_seams()),
            Err(DistroError::UnsupportedUbuntu("20.04".into()))
        );
    }

    #[test]
    fn rejects_rocky() {
        let d = TempDir::new().unwrap();
        let p = write_os_release(&d, "ID=rocky\nVERSION_ID=9.4\n");
        assert_eq!(
            detect_distro(&p, &no_seams()),
            Err(DistroError::UnsupportedDistro("rocky".into()))
        );
    }

    #[test]
    fn rejects_almalinux_8() {
        let d = TempDir::new().unwrap();
        let p = write_os_release(&d, "ID=almalinux\nVERSION_ID=8\n");
        assert_eq!(
            detect_distro(&p, &no_seams()),
            Err(DistroError::UnsupportedAlma("8".into()))
        );
    }

    #[test]
    fn rejects_almalinux_10() {
        let d = TempDir::new().unwrap();
        let p = write_os_release(&d, "ID=almalinux\nVERSION_ID=10\n");
        assert_eq!(
            detect_distro(&p, &no_seams()),
            Err(DistroError::UnsupportedAlma("10".into()))
        );
    }

    #[test]
    fn unreadable_os_release_is_refused_when_not_skipping() {
        let d = TempDir::new().unwrap();
        let p = d.path().join("does-not-exist");
        assert!(matches!(
            detect_distro(&p, &no_seams()),
            Err(DistroError::Unreadable(_))
        ));
    }

    // --- AGENTLINUX_SKIP_DISTRO_CHECK seam ---

    #[test]
    fn skip_check_seeds_rhel_from_almalinux_id() {
        let d = TempDir::new().unwrap();
        let p = write_os_release(&d, "ID=almalinux\nVERSION_ID=9.4\n");
        let env = DetectEnv {
            skip_check: true,
            family_override: None,
        };
        assert_eq!(
            detect_distro(&p, &env).unwrap(),
            Distro {
                family: Family::Rhel,
                version: "unchecked".into()
            }
        );
    }

    #[test]
    fn skip_check_defaults_debian_for_non_almalinux_id() {
        let d = TempDir::new().unwrap();
        let p = write_os_release(&d, "ID=ubuntu\nVERSION_ID=24.04\n");
        let env = DetectEnv {
            skip_check: true,
            family_override: None,
        };
        assert_eq!(
            detect_distro(&p, &env).unwrap(),
            Distro {
                family: Family::Debian,
                version: "unchecked".into()
            }
        );
    }

    #[test]
    fn skip_check_explicit_family_override_wins() {
        let d = TempDir::new().unwrap();
        // ID says ubuntu, but the explicit override says rhel — override wins.
        let p = write_os_release(&d, "ID=ubuntu\nVERSION_ID=24.04\n");
        let env = DetectEnv {
            skip_check: true,
            family_override: Some("rhel".into()),
        };
        assert_eq!(detect_distro(&p, &env).unwrap().family, Family::Rhel);
    }

    #[test]
    fn skip_check_missing_file_defaults_debian() {
        let d = TempDir::new().unwrap();
        let p = d.path().join("nonexistent");
        let env = DetectEnv {
            skip_check: true,
            family_override: None,
        };
        assert_eq!(
            detect_distro(&p, &env).unwrap(),
            Distro {
                family: Family::Debian,
                version: "unchecked".into()
            }
        );
    }

    #[test]
    fn os_release_value_strips_quotes_and_skips_comments() {
        let c = "# comment\nID=\"ubuntu\"\nVERSION_ID='24.04'\n";
        assert_eq!(os_release_value(c, "ID").as_deref(), Some("ubuntu"));
        assert_eq!(os_release_value(c, "VERSION_ID").as_deref(), Some("24.04"));
    }
}
