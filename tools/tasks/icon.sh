#!/usr/bin/env bash
#MISE description="Render App/AppIcon.svg into App/Assets.xcassets, AppIcon and the purple AppIconDev (needs node)"
set -euo pipefail
npm install --silent --no-save --prefix .tmp/build/icon-tools @resvg/resvg-js@2.6.2
NODE_PATH=.tmp/build/icon-tools/node_modules node tools/tasks/lib/render-icon.js
