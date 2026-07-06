import { View } from 'react-native'
import { useSafeAreaInsets } from 'react-native-safe-area-context'
import { HyggeLogoBadge } from './HyggeLogoBadge'

// The shared placement for the brand mark: pinned to the top-right safe-area
// corner so it lands in the same spot on every screen. Drop a single
// <ScreenBadge /> into a screen and the badge renders identically everywhere.
//
// It's a decorative stamp, not a control, so it never intercepts touches — the
// header controls it sits beside stay fully tappable underneath.
export function ScreenBadge() {
  const insets = useSafeAreaInsets()
  return (
    <View
      pointerEvents="none"
      style={{ position: 'absolute', top: insets.top + 8, right: 16, zIndex: 50 }}
    >
      <HyggeLogoBadge />
    </View>
  )
}
