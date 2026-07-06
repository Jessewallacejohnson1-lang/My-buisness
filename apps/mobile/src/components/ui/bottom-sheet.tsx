import { useEffect, useState, type ReactNode } from 'react'
import { Modal, Pressable, Text, View, useWindowDimensions, type DimensionValue } from 'react-native'
import { GestureHandlerRootView, Gesture, GestureDetector } from 'react-native-gesture-handler'
import Animated, {
  Easing, Extrapolation, interpolate, runOnJS,
  useAnimatedStyle, useReducedMotion, useSharedValue, withSpring, withTiming,
} from 'react-native-reanimated'
import { C, F, HAIRLINE } from '../../theme'
import { CloseIcon } from '../icons'

const SPRING = { damping: 22, stiffness: 240, mass: 0.9 }
const OUT_MS = 220

/**
 * The one dismissible bottom sheet for the whole app. Every sheet used to
 * re-roll its own dismissal, so the same three gaps kept recurring: a grab
 * handle wired to nothing, a close X in the faintest gray in the system, and
 * motion that ignored reduce-motion. This makes "dismissible correctly" the
 * default — and gives the user three independent, guaranteed exits so no input
 * method is ever stranded:
 *
 *   1. a **visible close chip** (the guaranteed tap/click target — mouse + touch)
 *   2. **backdrop tap** to dismiss
 *   3. real **swipe-down on the handle** (the handle finally tells the truth)
 *
 * Motion is owned here (the RN Modal is `animationType="none"`) so it can honor
 * reduce-motion: spring up on open, quick ease-out on close, and — when the OS
 * asks for no motion — an instant show/hide with the swipe still dismissing.
 */
export function BottomSheet({
  open, onClose, title, maxHeight = '64%', children,
}: {
  open: boolean
  onClose: () => void
  title?: string
  /** How tall the sheet may grow. Percent of screen or px. */
  maxHeight?: DimensionValue
  children?: ReactNode
}) {
  const { height: WIN_H } = useWindowDimensions()
  const reduce = useReducedMotion()
  const [render, setRender] = useState(open)
  const ty = useSharedValue(WIN_H) // sheet translateY: 0 = open, WIN_H = offscreen
  const h = useSharedValue(WIN_H)  // measured sheet height (backdrop fade + dismiss threshold)

  // Mount + animate. The effect owns ALL entrance/exit motion; tap/backdrop/drag
  // handlers just call onClose() and let the open→false pass drive the exit.
  useEffect(() => {
    if (open) {
      setRender(true)
      ty.value = WIN_H
      ty.value = reduce ? 0 : withSpring(0, SPRING)
    } else if (render) {
      if (reduce) { ty.value = WIN_H; setRender(false) }
      else ty.value = withTiming(WIN_H, { duration: OUT_MS, easing: Easing.in(Easing.cubic) }, (f) => {
        if (f) runOnJS(setRender)(false)
      })
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, reduce])

  // Grab-handle swipe: track downward drag, dismiss past 25% of the sheet's
  // height or on a firm flick — the gesture that makes the handle honest.
  const pan = Gesture.Pan()
    .activeOffsetY(8)
    .onUpdate((e) => { 'worklet'; ty.value = Math.max(0, e.translationY) })
    .onEnd((e) => {
      'worklet'
      if (e.translationY > h.value * 0.25 || e.velocityY > 600) runOnJS(onClose)()
      else ty.value = withSpring(0, SPRING)
    })

  const sheetStyle = useAnimatedStyle(() => ({ transform: [{ translateY: ty.value }] }))
  const backdropStyle = useAnimatedStyle(() => ({
    opacity: interpolate(ty.value, [0, h.value], [1, 0], Extrapolation.CLAMP),
  }))

  return (
    <Modal visible={render} transparent animationType="none" onRequestClose={onClose} statusBarTranslucent>
      <GestureHandlerRootView style={{ flex: 1 }}>
        {/* backdrop — tap anywhere to close */}
        <Animated.View style={[{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, backgroundColor: 'rgba(20,18,14,0.34)' }, backdropStyle]}>
          <Pressable style={{ flex: 1 }} onPress={onClose} accessibilityRole="button" accessibilityLabel="Close" />
        </Animated.View>

        <Animated.View
          onLayout={(e) => { h.value = e.nativeEvent.layout.height }}
          style={[{
            position: 'absolute', left: 0, right: 0, bottom: 0, maxHeight,
            backgroundColor: C.paper, borderTopLeftRadius: 24, borderTopRightRadius: 24,
            borderTopWidth: 1, borderColor: HAIRLINE,
            shadowColor: '#000000', shadowOpacity: 0.14, shadowRadius: 28, shadowOffset: { width: 0, height: -6 }, elevation: 16,
          }, sheetStyle]}
        >
          {/* draggable header zone: handle + optional title */}
          <GestureDetector gesture={pan}>
            <View style={{ paddingTop: 10, paddingBottom: title ? 8 : 2 }}>
              <View style={{ alignSelf: 'center', width: 40, height: 5, borderRadius: 2.5, backgroundColor: 'rgba(0,0,0,0.16)' }} />
              {!!title && (
                <Text numberOfLines={1} style={{ fontWeight: F.display, fontSize: 18, color: C.ink, paddingLeft: 20, paddingRight: 62, marginTop: 12 }}>{title}</Text>
              )}
            </View>
          </GestureDetector>

          {/* always-visible close — the guaranteed exit for mouse + touch */}
          <Pressable
            onPress={onClose}
            hitSlop={12}
            accessibilityRole="button"
            accessibilityLabel="Close"
            style={({ pressed }) => ({
              position: 'absolute', top: 14, right: 14, width: 32, height: 32, borderRadius: 16,
              alignItems: 'center', justifyContent: 'center',
              backgroundColor: C.paper100, opacity: pressed ? 0.6 : 1,
            })}
          >
            <CloseIcon size={16} color={C.ink2} />
          </Pressable>

          {children}
        </Animated.View>
      </GestureHandlerRootView>
    </Modal>
  )
}
