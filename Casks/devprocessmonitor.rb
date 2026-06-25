cask "devprocessmonitor" do
  version "1.12.2"
  sha256 "54c517e8fce7e68593e8672a8ddc2e9c69656e5be3376ddebefa0af7f6d40007"

  url "https://github.com/FagundesCristianoF/process-monitor/releases/download/v#{version}/ProcessMonitor.zip"
  name "Process Monitor"
  desc "Menu bar app that monitors memory usage for developer processes"
  homepage "https://github.com/FagundesCristianoF/process-monitor"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :ventura

  app "ProcessMonitor.app"

  auto_updates true

  zap trash: [
    "~/Library/Preferences/com.cristianofagundes.ProcessMonitor.plist",
    "~/Library/Application Support/ProcessMonitor",
    "~/Library/Saved Application State/com.cristianofagundes.ProcessMonitor.savedState",
  ]
end
