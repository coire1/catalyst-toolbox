mod community_advisors;
mod veterans;
mod voters;

use color_eyre::Report;
use structopt::StructOpt;

#[derive(StructOpt)]
#[structopt(rename_all = "kebab-case")]
pub enum Rewards {
    /// Calculate rewards for voters base on their stake
    Voters(voters::VotersRewards),

    /// Calculate community advisors rewards
    CommunityAdvisors(community_advisors::CommunityAdvisors),

    /// Calculate rewards for veteran community advisors
    Veterans(veterans::VeteransRewards),
}

impl Rewards {
    pub fn exec(self) -> Result<(), Report> {
        match self {
            Rewards::Voters(cmd) => cmd.exec(),
            Rewards::CommunityAdvisors(cmd) => cmd.exec(),
            Rewards::Veterans(cmd) => cmd.exec(),
        }
    }
}
