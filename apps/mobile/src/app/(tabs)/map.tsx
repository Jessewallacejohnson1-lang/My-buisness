import { TownMap } from '../../components/TownMap'

// The map itself is platform-split: components/TownMap.tsx is the native
// react-native-maps screen; TownMap.web.tsx is the website fallback (the
// maps library is native-only and breaks the web bundle if imported there).
export default function MapTab() {
  return <TownMap />
}
