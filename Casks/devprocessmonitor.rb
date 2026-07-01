cask "devprocessmonitor" do
  version "1.13.0"
  sha256 "01e674bef84f161be54e772690dae440478adb5a54c93ab24e034a8f12dfa6f7"

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
