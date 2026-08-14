version       = "0.1.0"
author        = "nimbase"
description   = "Self-test package used by the action's own CI"
license       = "MIT"

task test, "run the self-test sample":
  exec "nim c -r sample.nim"
