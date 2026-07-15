import React from 'react'
import { Platform, Pressable, StyleSheet, Text, View } from 'react-native'
import { Image } from 'expo-image'
import { LinearGradient } from 'expo-linear-gradient'
import Animated, { Easing, FadeInDown, useReducedMotion } from 'react-native-reanimated'
import { C, F, RADIUS, CARD_SHADOW } from '../theme'
import { CheckIcon } from './icons'

// One photo-forward tile for the whole Activities browse surface. A real photo
// when the item has one; otherwise a UNIFIED CORAL gradient — honest by design,
// never fake imagery. Coral tile and real photo share the SAME shape, scrim,
// tag, and title so a column of them reads as one calm system. Structure mirrors
// AroundTown: an un-clipped shadow host → a clipped face → layered fills →
// text-shadow title → press-scale + reduced-motion. The Join chip is a SIBLING
// of the face (never nested), so edge taps on Join don't fall through to open
// the sheet — and on web it renders as a real <button> beside, not inside, the
// face button (the RN-web invalid-DOM fix).

export type ActivityKind = 'event' | 'club' | 'trail'

export interface ActivityJoin {
  joined: boolean
  onToggle: () => void
}

export interface ActivityTileProps {
  kind: ActivityKind
  title: string
  /** Real photo when present; otherwise the unified coral gradient tile. */
  imageUrl?: string | null
  /** Tap to open the detail sheet. Omit → a non-interactive hero (sheet banner). */
  onPress?: () => void
  /** Club Join control only — floats top-right as a SIBLING tap target. Omit for events/trails. */
  join?: ActivityJoin
  /** Running list index → capped entrance stagger. Omit → no entrance (heroes). */
  index?: number
  /** px height. 200 = browse list (default); 140 = sheet hero. */
  height?: number
  /** Overrides the default "Kind: Title" screen-reader label. */
  accessibilityLabel?: string
}

const DEFAULT_HEIGHT = 200
const TILE_RADIUS = RADIUS.xl // 20
const TILE_PAD = 16

// Unified coral tile — a subtle diagonal warmth, IDENTICAL on every generated
// tile. Also the load placeholder behind photos (a photo settles out of the
// shared coral substrate — no white flash). Top is an honest tint of the
// accent; mid = C.accent; foot = C.accentPressed.
const CORAL_COLORS = ['#FF7A63', '#FF6B57', '#E0553F'] as const
const CORAL_LOCATIONS = [0, 0.5, 1] as const
const CORAL_START = { x: 0, y: 0 }
const CORAL_END = { x: 1, y: 1 }

// One scrim over BOTH coral and photo tiles (this identity is the cohesion).
// The tag + title BOTH sit in the deep foot band (AroundTown's stacked-at-foot
// pattern), so a strong foot — not a top stop — carries their legibility over
// any photo, bright ones included. A light top stop only adds gentle depth.
const SCRIM_COLORS = ['rgba(20,16,12,0.22)', 'rgba(20,16,12,0)', 'rgba(20,16,12,0.32)', 'rgba(20,16,12,0.92)'] as const
const SCRIM_LOCATIONS = [0, 0.34, 0.6, 1] as const
// Warms cold/blue photos into the coral family (imperceptible as a filter).
const PHOTO_WASH = 'rgba(255,107,87,0.08)'

const TEXT_SHADOW = { textShadowColor: 'rgba(0,0,0,0.45)', textShadowOffset: { width: 0, height: 1 }, textShadowRadius: 8 } as const
const KIND_LABEL: Record<ActivityKind, string> = { event: 'Event', club: 'Club', trail: 'Trail' }

/** The layered fill + tag + title. Shared by the interactive face and the hero. */
function TileFace({ kind, title, imageUrl }: { kind: ActivityKind; title: string; imageUrl?: string | null }) {
  return (
    <>
      <LinearGradient colors={CORAL_COLORS} locations={CORAL_LOCATIONS} start={CORAL_START} end={CORAL_END} style={StyleSheet.absoluteFill} />
      {!!imageUrl && (
        <>
          <Image source={{ uri: imageUrl }} style={StyleSheet.absoluteFill} contentFit="cover" transition={260} cachePolicy="memory-disk" recyclingKey={imageUrl} />
          <View style={[StyleSheet.absoluteFill, { backgroundColor: PHOTO_WASH }]} pointerEvents="none" />
        </>
      )}
      <LinearGradient colors={SCRIM_COLORS} locations={SCRIM_LOCATIONS} style={StyleSheet.absoluteFill} pointerEvents="none" />
      {/* Tag + title stacked at the foot, both inside the deep-scrim band. */}
      <Text style={{ fontSize: 11, fontWeight: F.sansSemi, letterSpacing: 1.5, textTransform: 'uppercase', color: 'rgba(253,252,248,0.92)', marginBottom: 5, ...TEXT_SHADOW }}>
        {KIND_LABEL[kind]}
      </Text>
      <Text numberOfLines={2} style={{ fontSize: 23, lineHeight: 27, fontWeight: F.display, letterSpacing: -0.3, color: '#FDFCF8', ...TEXT_SHADOW }}>
        {title}
      </Text>
    </>
  )
}

function ActivityTileBase({ kind, title, imageUrl, onPress, join, index, height = DEFAULT_HEIGHT, accessibilityLabel }: ActivityTileProps) {
  const reduce = useReducedMotion()
  // Stagger on native only: FadeInDown starts at opacity 0, and a reveal that
  // never fires on a hidden/headless web render would ship blank — so web keeps
  // the already-visible default (expo-image's fade covers the settle there).
  const entering = reduce || index == null || Platform.OS === 'web'
    ? undefined
    : FadeInDown.duration(260).delay(Math.min(index, 6) * 40).easing(Easing.out(Easing.cubic))

  return (
    // Outer = shadow host (NOT clipped, no overflow:hidden) so the elevation
    // shows. backgroundColor gives Android an opaque surface to cast from and a
    // coral backstop behind the clipped face (never actually visible).
    <Animated.View entering={entering} style={{ height, borderRadius: TILE_RADIUS, backgroundColor: C.accent, ...CARD_SHADOW }}>
      {onPress ? (
        <Pressable
          onPress={onPress}
          accessibilityRole="button"
          accessibilityLabel={accessibilityLabel ?? `${KIND_LABEL[kind]}: ${title}`}
          accessibilityHint="Opens details"
          style={({ pressed }) => ({ flex: 1, borderRadius: TILE_RADIUS, overflow: 'hidden', justifyContent: 'flex-end', padding: TILE_PAD, transform: [{ scale: pressed ? 0.97 : 1 }] })}
        >
          <TileFace kind={kind} title={title} imageUrl={imageUrl} />
        </Pressable>
      ) : (
        <View style={{ flex: 1, borderRadius: TILE_RADIUS, overflow: 'hidden', justifyContent: 'flex-end', padding: TILE_PAD }}>
          <TileFace kind={kind} title={title} imageUrl={imageUrl} />
        </View>
      )}

      {join && (
        <Pressable
          onPress={join.onToggle}
          hitSlop={8}
          accessibilityRole="button"
          accessibilityState={{ selected: join.joined }}
          accessibilityLabel={join.joined ? `Leave ${title}` : `Join ${title}`}
          style={({ pressed }) => ({ position: 'absolute', top: 12, right: 12, height: 34, paddingHorizontal: 14, borderRadius: 100, flexDirection: 'row', alignItems: 'center', gap: 5, backgroundColor: '#FDFBF7', transform: [{ scale: pressed ? 0.97 : 1 }] })}
        >
          {join.joined && <CheckIcon size={13} color={C.moss700} />}
          <Text style={{ fontWeight: F.sansSemi, fontSize: 13, color: join.joined ? C.moss700 : C.ink }}>{join.joined ? 'Joined' : 'Join'}</Text>
        </Pressable>
      )}
    </Animated.View>
  )
}

export const ActivityTile = React.memo(ActivityTileBase)

/** Loading placeholder at the true tile silhouette — static, neutral, no jump. */
export function ActivityTileSkeleton({ height = DEFAULT_HEIGHT }: { height?: number }) {
  return (
    <View style={{ height, borderRadius: TILE_RADIUS, backgroundColor: C.paper100, overflow: 'hidden', justifyContent: 'flex-end', padding: TILE_PAD }}>
      <View style={{ position: 'absolute', top: TILE_PAD, left: TILE_PAD, width: 48, height: 10, borderRadius: 5, backgroundColor: C.paper200 }} />
      <View style={{ width: '62%', height: 22, borderRadius: 6, backgroundColor: C.paper200 }} />
    </View>
  )
}
