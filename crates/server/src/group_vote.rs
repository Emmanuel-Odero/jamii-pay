//! Group withdrawal-vote tally — a pure function, deliberately kept out
//! of SQL so it's exercised by real unit tests rather than only being
//! observable through the HTTP layer. Ported verbatim from
//! `designs/jammii-pay-prototype.html`'s `groupVote` screen math:
//! majority (>50% of *voting power*, not headcount) passes; any single
//! veto blocks the payout unconditionally regardless of the approve
//! share; withheld power is excluded from the payout amount rather than
//! blocking it.

use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "text", rename_all = "lowercase")]
pub enum Choice {
    Approve,
    Withhold,
    Veto,
}

pub struct MemberVote {
    pub member_id: Uuid,
    /// This member's share of total voting power, already normalized
    /// (0.0-1.0) by the caller per the group's `power_scheme`.
    pub power: f64,
    /// `None` — hasn't voted yet ("not voted", per the prototype's
    /// legend — counts toward `total_power` but neither approve nor
    /// withheld/veto).
    pub choice: Option<Choice>,
}

#[derive(Debug, PartialEq)]
pub struct VoteOutcome {
    pub approve_power: f64,
    pub withheld_power: f64,
    pub blocked_by_veto: bool,
    /// Majority reached (`approve_power > total_power / 2`) — independent
    /// of `blocked_by_veto`; a request can simultaneously "pass" the
    /// majority bar and still be blocked.
    pub passes_majority: bool,
    /// The amount that would actually move if executed right now. Zero
    /// whenever `blocked_by_veto` or `!passes_majority`.
    pub payout_usd_cents: i64,
}

pub fn tally(amount_usd_cents: i64, votes: &[MemberVote]) -> VoteOutcome {
    let total_power: f64 = votes.iter().map(|v| v.power).sum();
    let approve_power: f64 = votes
        .iter()
        .filter(|v| v.choice == Some(Choice::Approve))
        .map(|v| v.power)
        .sum();
    let withheld_power: f64 = votes
        .iter()
        .filter(|v| v.choice == Some(Choice::Withhold))
        .map(|v| v.power)
        .sum();
    let blocked_by_veto = votes.iter().any(|v| v.choice == Some(Choice::Veto));
    let passes_majority = total_power > 0.0 && approve_power > total_power / 2.0;

    let payout_usd_cents = if blocked_by_veto || !passes_majority || total_power <= 0.0 {
        0
    } else {
        ((amount_usd_cents as f64) * (1.0 - withheld_power / total_power)).round() as i64
    };

    VoteOutcome {
        approve_power,
        withheld_power,
        blocked_by_veto,
        passes_majority,
        payout_usd_cents,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn vote(power: f64, choice: Option<Choice>) -> MemberVote {
        MemberVote { member_id: Uuid::new_v4(), power, choice }
    }

    #[test]
    fn majority_approve_passes_and_pays_in_full() {
        let votes = vec![
            vote(0.4, Some(Choice::Approve)),
            vote(0.35, Some(Choice::Approve)),
            vote(0.25, None),
        ];
        let outcome = tally(10_000, &votes);
        assert!(outcome.passes_majority);
        assert!(!outcome.blocked_by_veto);
        assert_eq!(outcome.payout_usd_cents, 10_000);
    }

    #[test]
    fn exactly_half_does_not_pass() {
        let votes = vec![vote(0.5, Some(Choice::Approve)), vote(0.5, Some(Choice::Withhold))];
        let outcome = tally(10_000, &votes);
        assert!(!outcome.passes_majority);
        assert_eq!(outcome.payout_usd_cents, 0);
    }

    #[test]
    fn single_veto_blocks_regardless_of_majority() {
        let votes = vec![
            vote(0.6, Some(Choice::Approve)),
            vote(0.3, Some(Choice::Approve)),
            vote(0.1, Some(Choice::Veto)),
        ];
        let outcome = tally(10_000, &votes);
        assert!(outcome.passes_majority); // majority reached...
        assert!(outcome.blocked_by_veto); // ...but still blocked
        assert_eq!(outcome.payout_usd_cents, 0);
    }

    #[test]
    fn withheld_share_is_excluded_from_payout() {
        // 60% approve, 20% withheld, 20% not voted — majority passes
        // (60% > 50%), payout excludes the withheld 20%.
        let votes = vec![
            vote(0.6, Some(Choice::Approve)),
            vote(0.2, Some(Choice::Withhold)),
            vote(0.2, None),
        ];
        let outcome = tally(10_000, &votes);
        assert!(outcome.passes_majority);
        assert_eq!(outcome.payout_usd_cents, 8_000);
    }

    #[test]
    fn no_votes_yet_does_not_pass() {
        let votes = vec![vote(0.5, None), vote(0.5, None)];
        let outcome = tally(10_000, &votes);
        assert!(!outcome.passes_majority);
        assert_eq!(outcome.payout_usd_cents, 0);
    }
}
