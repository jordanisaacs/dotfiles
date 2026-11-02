//! Read-only probe of upstream app-rummage's public API, without exe fallbacks.
use std::num::NonZeroU32;
use std::path::PathBuf;

struct NoProcess;

impl app_rummage::Process for NoProcess {
    fn pid(&self) -> NonZeroU32 {
        unreachable!()
    }
    fn executable_path(&self) -> Option<PathBuf> {
        unreachable!()
    }
    fn name(&self) -> &str {
        unreachable!()
    }
}

fn main() {
    let apps = app_rummage::installed_apps();
    let mut running = app_rummage::running_apps(&apps, std::iter::empty::<&NoProcess>());
    running.sort_by(|a, b| a.0.id.cmp(&b.0.id));
    for (app, pids) in running {
        let pids = pids.iter().map(|pid| pid.get()).collect::<Vec<_>>();
        println!("{:?}\t{:?}", app.id, pids);
    }
}
