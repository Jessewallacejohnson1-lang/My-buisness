import Svg, { Circle, Line, Path, Polyline, Rect } from 'react-native-svg'
import { C } from '../theme'

export type TabId = 'home' | 'activities' | 'calendar' | 'add'
export type Scope = 'today' | 'week' | 'going'

export function TabIcon({ id, active }: { id: TabId; active: boolean }) {
  const c = active ? C.moss700 : C.ink3
  const sw = id === 'add' ? 2.1 : 1.7
  const p = { fill: 'none', stroke: c, strokeWidth: sw, strokeLinecap: 'round' as const, strokeLinejoin: 'round' as const }
  if (id === 'activities')
    return (
      <Svg width={22} height={22} viewBox="0 0 24 24">
        {/* Compass: outer circle + cardinal needle */}
        <Circle cx={12} cy={12} r={9} {...p} />
        <Path d="M16.2 7.8 13.5 13.5 7.8 16.2 10.5 10.5z" {...p} />
      </Svg>
    )
  if (id === 'home')
    return (
      <Svg width={22} height={22} viewBox="0 0 24 24">
        <Path d="M3 11.4 12 4l9 7.4" {...p} />
        <Path d="M5.6 9.8v9.7c0 .3.2.5.5.5h11.8c.3 0 .5-.2.5-.5V9.8" {...p} />
      </Svg>
    )
  if (id === 'calendar')
    return (
      <Svg width={22} height={22} viewBox="0 0 24 24">
        <Rect x={3} y={4} width={18} height={18} rx={2} {...p} />
        <Line x1={16} y1={2} x2={16} y2={6} {...p} />
        <Line x1={8} y1={2} x2={8} y2={6} {...p} />
        <Line x1={3} y1={10} x2={21} y2={10} {...p} />
      </Svg>
    )
  if (id === 'add')
    return (
      <Svg width={22} height={22} viewBox="0 0 24 24">
        <Circle cx={12} cy={12} r={9} {...p} />
        <Line x1={12} y1={8} x2={12} y2={16} {...p} />
        <Line x1={8} y1={12} x2={16} y2={12} {...p} />
      </Svg>
    )
  return null
}

export function CheckIcon({ size = 14, color = C.paper }: { size?: number; color?: string }) {
  return (
    <Svg width={size} height={size} viewBox="0 0 14 14">
      <Polyline points="2 7 5.5 10.5 12 3.5" fill="none" stroke={color} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" />
    </Svg>
  )
}

export function SearchIcon({ color = C.ink }: { color?: string }) {
  return (
    <Svg width={19} height={19} viewBox="0 0 24 24">
      <Circle cx={11} cy={11} r={7} fill="none" stroke={color} strokeWidth={1.9} strokeLinecap="round" strokeLinejoin="round" />
      <Line x1={16.5} y1={16.5} x2={21} y2={21} fill="none" stroke={color} strokeWidth={1.9} strokeLinecap="round" strokeLinejoin="round" />
    </Svg>
  )
}

export function AccountIcon({ color = C.ink }: { color?: string }) {
  return (
    <Svg width={20} height={20} viewBox="0 0 24 24">
      <Circle cx={12} cy={9} r={3.4} fill="none" stroke={color} strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" />
      <Path d="M5.5 20c0-3.6 2.9-6 6.5-6s6.5 2.4 6.5 6" fill="none" stroke={color} strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" />
    </Svg>
  )
}

export function ScopeIcon({ id, active }: { id: Scope; active: boolean }) {
  const c = active ? C.paper : C.ink3
  const p = { fill: 'none', stroke: c, strokeWidth: 1.7, strokeLinecap: 'round' as const, strokeLinejoin: 'round' as const }
  if (id === 'today')
    return (
      <Svg width={14} height={14} viewBox="0 0 24 24">
        <Circle cx={12} cy={12} r={4.2} {...p} />
        <Line x1={12} y1={2.5} x2={12} y2={5} {...p} /><Line x1={12} y1={19} x2={12} y2={21.5} {...p} />
        <Line x1={2.5} y1={12} x2={5} y2={12} {...p} /><Line x1={19} y1={12} x2={21.5} y2={12} {...p} />
        <Line x1={5.4} y1={5.4} x2={7.1} y2={7.1} {...p} /><Line x1={16.9} y1={16.9} x2={18.6} y2={18.6} {...p} />
        <Line x1={16.9} y1={7.1} x2={18.6} y2={5.4} {...p} /><Line x1={5.4} y1={18.6} x2={7.1} y2={16.9} {...p} />
      </Svg>
    )
  if (id === 'week')
    return (
      <Svg width={14} height={14} viewBox="0 0 24 24">
        <Rect x={3} y={4.5} width={18} height={16.5} rx={2.5} {...p} /><Line x1={3} y1={9} x2={21} y2={9} {...p} />
        <Line x1={8} y1={2.5} x2={8} y2={6} {...p} /><Line x1={16} y1={2.5} x2={16} y2={6} {...p} />
      </Svg>
    )
  return (
    <Svg width={14} height={14} viewBox="0 0 24 24">
      <Circle cx={12} cy={12} r={9} {...p} /><Polyline points="8.4 12 11 14.6 15.6 9.4" {...p} />
    </Svg>
  )
}

export function CloseIcon({ size = 18, color = C.ink3 }: { size?: number; color?: string }) {
  return (
    <Svg width={size} height={size} viewBox="0 0 18 18">
      <Line x1={3} y1={3} x2={15} y2={15} fill="none" stroke={color} strokeWidth={2} strokeLinecap="round" />
      <Line x1={15} y1={3} x2={3} y2={15} fill="none" stroke={color} strokeWidth={2} strokeLinecap="round" />
    </Svg>
  )
}

export function PlusIcon({ size = 14, color = C.ink2 }: { size?: number; color?: string }) {
  return (
    <Svg width={size} height={size} viewBox="0 0 15 15">
      <Line x1={7.5} y1={2} x2={7.5} y2={13} fill="none" stroke={color} strokeWidth={2} strokeLinecap="round" />
      <Line x1={2} y1={7.5} x2={13} y2={7.5} fill="none" stroke={color} strokeWidth={2} strokeLinecap="round" />
    </Svg>
  )
}

export function PinIcon({ size = 13, color = C.sky600 }: { size?: number; color?: string }) {
  return (
    <Svg width={size} height={size} viewBox="0 0 24 24">
      <Path d="M12 21c4-4.5 7-7.6 7-11a7 7 0 1 0-14 0c0 3.4 3 6.5 7 11Z" fill="none" stroke={color} strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" />
      <Circle cx={12} cy={10} r={2.4} fill="none" stroke={color} strokeWidth={1.8} />
    </Svg>
  )
}
