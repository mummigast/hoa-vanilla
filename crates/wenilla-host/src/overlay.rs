//! Loose files served over the chain: a game folder's own `Interface\GlueXML` and
//! `Interface\AddOns`, which the native client reads off disk beside `Data` and the page cannot.
//! A name under one of [`ROOTS`] is looked up in the overlay folder first, a path component at a
//! time and ignoring case as the reference's file system does, then in the chain. Nothing outside
//! those roots is reachable, so the overlay cannot serve the rest of the folder.

use std::path::{Path, PathBuf};

/// The chain prefixes the overlay answers for, lowercase, `\`-separated.
const ROOTS: [&str; 2] = ["interface\\gluexml\\", "interface\\addons\\"];

/// The folder holding the loose `Interface` tree: the game folder, `Data`'s parent.
#[derive(Clone, Debug)]
pub struct Overlay {
    root: PathBuf,
}

impl Overlay {
    pub fn new(root: PathBuf) -> Self {
        Self { root }
    }

    /// The file a chain name maps to, when it is under [`ROOTS`] and exists.
    pub fn find(&self, name: &str) -> Option<PathBuf> {
        let lower = name.to_ascii_lowercase();
        if !ROOTS.iter().any(|r| lower.starts_with(r)) {
            return None;
        }
        let mut path = self.root.clone();
        for part in name.split('\\') {
            if part.is_empty() || part == "." || part == ".." {
                return None;
            }
            path = child_ignoring_case(&path, part)?;
        }
        path.is_file().then_some(path)
    }

    /// Every file under [`ROOTS`], as chain names (`Interface\AddOns\X\X.toc`).
    pub fn names(&self) -> Vec<String> {
        let mut out = Vec::new();
        for root in ROOTS {
            let mut dir = self.root.clone();
            let mut prefix = String::new();
            let mut found = true;
            for part in root.trim_end_matches('\\').split('\\') {
                match child_ignoring_case(&dir, part) {
                    Some(d) => {
                        prefix.push_str(&d.file_name().unwrap_or_default().to_string_lossy());
                        prefix.push('\\');
                        dir = d;
                    }
                    None => {
                        found = false;
                        break;
                    }
                }
            }
            if found {
                walk(&dir, &prefix, &mut out);
            }
        }
        out
    }
}

fn child_ignoring_case(dir: &Path, part: &str) -> Option<PathBuf> {
    let exact = dir.join(part);
    if exact.exists() {
        return Some(exact);
    }
    std::fs::read_dir(dir)
        .ok()?
        .flatten()
        .find(|e| e.file_name().to_string_lossy().eq_ignore_ascii_case(part))
        .map(|e| e.path())
}

fn walk(dir: &Path, prefix: &str, out: &mut Vec<String>) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    for e in entries.flatten() {
        let name = format!("{prefix}{}", e.file_name().to_string_lossy());
        let path = e.path();
        if path.is_dir() {
            walk(&path, &format!("{name}\\"), out);
        } else if path.is_file() {
            out.push(name);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::Overlay;

    #[test]
    fn finds_names_under_the_roots_ignoring_case_and_nothing_else() {
        let dir = std::env::temp_dir().join(format!("wenilla-overlay-{}", std::process::id()));
        let addon = dir.join("Interface").join("AddOns").join("Hoa");
        std::fs::create_dir_all(&addon).unwrap();
        std::fs::write(addon.join("Hoa.toc"), "## Title: Hoa\n").unwrap();
        std::fs::write(dir.join("secret.txt"), "no").unwrap();
        let overlay = Overlay::new(dir.clone());
        assert!(overlay.find("interface\\addons\\hoa\\HOA.TOC").is_some());
        assert!(overlay.find("Interface\\AddOns\\..\\..\\secret.txt").is_none());
        assert!(overlay.find("secret.txt").is_none());
        assert_eq!(overlay.names(), vec!["Interface\\AddOns\\Hoa\\Hoa.toc".to_string()]);
        std::fs::remove_dir_all(dir).unwrap();
    }
}
