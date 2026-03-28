cask "lingothing" do
  version "0.1.34"
  sha256 "1d07a12328fab190e5082ae3c27ea4b92ffb12ab911d3510a4dad103f210a226"

  url "https://github.com/nhestrompia/lingothing/releases/download/v#{version}/LingoThing-#{version}.app.zip"
  name "LingoThing"
  desc "Menu bar language practice app"
  homepage "https://github.com/nhestrompia/lingothing"

  depends_on macos: ">= :sonoma"

  app "LingoThing.app"

  zap trash: [
    "~/Library/Application Support/LingoThing",
    "~/Library/Preferences/com.lingothing.app.plist",
  ]
end
