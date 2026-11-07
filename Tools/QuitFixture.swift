// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 HopeZaa

import AppKit

let application = NSApplication.shared
let accessory = Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool ?? false
application.setActivationPolicy(accessory ? .accessory : .regular)
application.run()
