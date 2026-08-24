cask "hyper-vpn" do
  version "1.1.5"
  sha256 "da1d6b17314d0c3cfa54d69faa3d9df909173808657ee963fb471bdc0185088e"

  url "https://dl.hypervpn.app/ladder/macos/10/da1d6b17314d/Hyper%20VPN_#{version}_universal.dmg"
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
  depends_on macos: :ventura

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
