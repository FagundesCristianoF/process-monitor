cask "devprocessmonitor" do
  version "1.2"
  sha256 "51ac0bbab4ef60d8627763f99d6a4081d3d46b3ba7de29f1824198e7829201f3"

  url "https://github.com/FagundesCristianoF/process-monitor/releases/download/v#{version}/ProcessMonitor.zip"
  name "Process Monitor"
  desc "Menu bar app that monitors memory usage for developer processes"
  homepage "https://github.com/FagundesCristianoF/process-monitor"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"

  app "ProcessMonitor.app"

  zap trash: [
    "~/Library/Preferences/com.cristianofagundes.ProcessMonitor.plist",
    "~/Library/Application Support/ProcessMonitor",
    "~/Library/Saved Application State/com.cristianofagundes.ProcessMonitor.savedState",
  ]
end
