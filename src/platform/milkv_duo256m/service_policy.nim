## Provides Milk-V Duo 256M service startup policy.


## Returns the initial svcmgtd argument string.
func serviceManagerArgs*(): cstring =
  "--no-network"
