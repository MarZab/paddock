// Renders App/AppIcon.svg into the app's AppIcon asset and a purple AppIconDev for the Debug build
// (every size macOS asks for).
// Run with `mise run icon`, which installs the renderer (resvg) under build/.
const { Resvg } = require('@resvg/resvg-js')
const fs = require('fs')
const path = require('path')

const root = path.join(__dirname, '../../..')
const source = fs.readFileSync(path.join(root, 'App/AppIcon.svg'), 'utf8')

// The installed app keeps the blue sky; Paddock Dev (the Debug build) gets a purple one so the two
// are told apart in the Dock.
const variants = [
  { name: 'AppIcon', svg: source },
  {
    name: 'AppIconDev',
    svg: source.replace('#1D3B55', '#3A1F5C').replace('#3C7189', '#8657B0'),
  },
]

for (const variant of variants) {
  const out = path.join(root, 'App/Assets.xcassets', `${variant.name}.appiconset`)
  fs.mkdirSync(out, { recursive: true })
  const images = []
  for (const points of [16, 32, 128, 256, 512]) {
    for (const scale of [1, 2]) {
      const pixels = points * scale
      const filename = `icon_${points}x${points}${scale === 2 ? '@2x' : ''}.png`
      const png = new Resvg(variant.svg, { fitTo: { mode: 'width', value: pixels } }).render().asPng()
      fs.writeFileSync(path.join(out, filename), png)
      images.push({ filename, idiom: 'mac', scale: `${scale}x`, size: `${points}x${points}` })
    }
  }
  const contents = { images, info: { author: 'xcode', version: 1 } }
  fs.writeFileSync(path.join(out, 'Contents.json'), JSON.stringify(contents, null, 2) + '\n')
}
fs.writeFileSync(path.join(root, 'App/Assets.xcassets/Contents.json'),
  JSON.stringify({ info: { author: 'xcode', version: 1 } }, null, 2) + '\n')
