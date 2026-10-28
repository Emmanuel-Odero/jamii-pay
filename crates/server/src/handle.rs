//! Payment-handle check digit. A deliberately simple weighted checksum —
//! good enough to catch a single mistyped/transposed character (the stated
//! goal in the design: "catches mistakes if someone types your name
//! wrong"), not a cryptographic property. Swap for a proper Damm/Verhoeff
//! algorithm if that single-error guarantee needs to be provable.

const ALPHABET: &[u8] = b"abcdefghijklmnopqrstuvwxyz0123456789";

pub fn compute_check_digit(base: &str) -> char {
    let mut acc: u64 = 0;
    for (i, byte) in base.as_bytes().iter().enumerate() {
        acc = acc.wrapping_add((*byte as u64).wrapping_mul((i as u64) + 1));
    }
    let idx = (acc % ALPHABET.len() as u64) as usize;
    ALPHABET[idx] as char
}

pub fn is_valid_base(base: &str) -> bool {
    let len_ok = (3..=20).contains(&base.len());
    let chars_ok = base
        .chars()
        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit());
    len_ok && chars_ok
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deterministic_for_same_input() {
        assert_eq!(
            compute_check_digit("amina7k3n"),
            compute_check_digit("amina7k3n")
        );
    }

    #[test]
    fn differs_for_transposed_input() {
        // Not a strict guarantee for every pair, but true for this one —
        // documents the intent rather than proving it generally.
        assert_ne!(
            compute_check_digit("amina7k3n"),
            compute_check_digit("amina7kn3")
        );
    }
}
