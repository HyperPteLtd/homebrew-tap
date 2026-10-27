cask "hyper-vpn" do
  version "1.2.3"
  sha256 "07303bba5cf1923c3b03072fe4ce5fda0de7d70362d5d3b8a14ec9322ba147f1"

  url "https://dl.hypervpn.app/ladder/macos/28/07303bba5cf1/HyperVPN-#{version}-macos-arm64.dmg"
  name "Hyper VPN"
  desc "VPN client by Hyper Network"
  homepage "https://hypervpn.app/"

  livecheck do
    url "https://hypervpn.app/v1/public/app/latest?platform=macos"
    strategy :json do |json|
      json.dig("data", "version_name")
    end
  end

  depends_on arch: :arm64
  depends_on macos: :sequoia

  app "Hyper VPN.app"

  uninstall launchctl: "com.hypernetsg.helper-service",
            quit:      "com.hypernetsg",
            delete:    [
              "/Library/LaunchDaemons/com.hypernetsg.helper-service.plist",
              "/Library/PrivilegedHelperTools/com.hypernetsg.helper-service.bundle",
            ]

  zap trash: [
    "~/Library/Application Support/com.hypernetsg",
    "~/Library/Caches/com.hypernetsg",
    "~/Library/Containers/com.hypernetsg.Extensions",
    "~/Library/Group Containers/3YNVW8CLGX.group.app.com.hypernetsg",
    "~/Library/HTTPStorages/com.hypernetsg",
    "~/Library/Logs/com.hypernetsg",
    "~/Library/Preferences/com.hypernetsg.plist",
    "~/Library/Saved Application State/com.hypernetsg.savedState",
    "~/Library/WebKit/com.hypernetsg",
  ]
end
