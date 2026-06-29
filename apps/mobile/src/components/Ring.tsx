import { useEffect } from 'react'
import { View, type ViewStyle } from 'react-native'
import Svg, { Circle, Defs, LinearGradient, Stop } from 'react-native-svg'
import Animated, {
  Easing, useAnimatedProps, useReducedMotion, useSharedValue, withTiming,
} from 'react-native-reanimated'

const ACircle = Animated.createAnimatedComponent(Circle)
// The premium ease — heavy, settled (from the high-end-visual-design spec).
const BEZIER = Easing.bezier(0.32, 0.72, 0, 1)
const clamp = (n: number) => Math.max(0, Math.min(1, n))

/** Animated circular progress ring with an optional 2-stop gradient stroke and
 *  center content. The arc sweeps in on mount (skipped under reduced motion). */
export function Ring({
  size = 116, stroke = 12, progress, color = '#3f9b6e', gradient, track = 'rgba(0,0,0,0.06)',
  id = 'ring', style, children,
}: {
  size?: number
  stroke?: number
  progress: number
  color?: string
  gradient?: [string, string]
  track?: string
  id?: string
  style?: ViewStyle
  children?: React.ReactNode
}) {
  const r = (size - stroke) / 2
  const circ = 2 * Math.PI * r
  const reduce = useReducedMotion()
  const p = useSharedValue(reduce ? clamp(progress) : 0)

  useEffect(() => {
    p.value = reduce ? clamp(progress) : withTiming(clamp(progress), { duration: 1100, easing: BEZIER })
  }, [progress, reduce, p])

  const animatedProps = useAnimatedProps(() => ({ strokeDashoffset: circ * (1 - p.value) }))
  const strokeColor = gradient ? `url(#${id})` : color

  return (
    <View style={[{ width: size, height: size, alignItems: 'center', justifyContent: 'center' }, style]}>
      <Svg width={size} height={size} style={{ position: 'absolute', transform: [{ rotate: '-90deg' }] }}>
        {gradient && (
          <Defs>
            <LinearGradient id={id} x1="0" y1="0" x2="1" y2="1">
              <Stop offset="0" stopColor={gradient[0]} />
              <Stop offset="1" stopColor={gradient[1]} />
            </LinearGradient>
          </Defs>
        )}
        <Circle cx={size / 2} cy={size / 2} r={r} stroke={track} strokeWidth={stroke} fill="none" />
        <ACircle
          cx={size / 2} cy={size / 2} r={r}
          stroke={strokeColor} strokeWidth={stroke} fill="none" strokeLinecap="round"
          strokeDasharray={circ} animatedProps={animatedProps}
        />
      </Svg>
      {children}
    </View>
  )
}
