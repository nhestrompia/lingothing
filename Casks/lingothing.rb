cask "lingothing" do
  version "0.1.0"
  sha256 "3670615e141ebdad1fc49731bcc1d65f0c125ffe8aaec23392d1c40a91af61a1"

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
