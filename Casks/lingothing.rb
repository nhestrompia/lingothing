cask "lingothing" do
  version "0.1.2"
  sha256 "55187915766eaed95b8623158d57f151f92c89154c7036d11331da7c75df7fc9"

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
