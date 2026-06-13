cask "devprocessmonitor" do
  version "1.9.0"
  sha256 "37787dc293786d1f58c333e99bfb792203f0fe3eccf55c210f98a8aee77968e4"

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
