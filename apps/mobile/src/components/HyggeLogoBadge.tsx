import { Text, View, type ViewStyle } from 'react-native'

// The Hygge brand mark: the wordmark set in Atkinson Hyperlegible Bold, white on a
// coral rectangle. Deliberately minimal (Life360 / Snapchat lockup) — a crisp,
// square-cornered rectangle so it reads as a printed stamp, not a button.
//
// This is the ONE place Atkinson Hyperlegible is used in the app; every other
// surface is the platform system font. The colors are fixed brand constants (not
// theme tokens) so the mark stays identical if the theme ever shifts — coral
// happens to match C.accent today, but the logo owns this hex.
const CORAL = '#FF6B57'
const WHITE = '#FFFFFF'

export function HyggeLogoBadge({ style }: { style?: ViewStyle }) {
  return (
    <View
      accessibilityRole="image"
      accessibilityLabel="Hygge"
      style={[
        {
          backgroundColor: CORAL,
          borderRadius: 0,
          paddingHorizontal: 11,
          paddingVertical: 5,
          alignSelf: 'flex-start',
          // A light lift so the mark holds over maps and photos without reading heavy.
          shadowColor: '#000000',
          shadowOpacity: 0.12,
          shadowRadius: 6,
          shadowOffset: { width: 0, height: 2 },
          elevation: 3,
        },
        style,
      ]}
    >
      <Text
        // A logo is a fixed asset — never let Dynamic Type resize it.
        allowFontScaling={false}
        style={{
          fontFamily: 'AtkinsonHyperlegible_700Bold',
          fontSize: 15,
          lineHeight: 18,
          color: WHITE,
          letterSpacing: 0.2,
        }}
      >
        Hygge
      </Text>
    </View>
  )
}
