import { useState } from 'react'
import { Modal, Pressable, Text } from 'react-native'
import { useRouter } from 'expo-router'
import * as Haptics from 'expo-haptics'
import { C, F, HAIRLINE, CARD_SHADOW } from '../theme'
import { AccountIcon, CloseIcon } from './icons'

export function AccountMenu({ name, onSignOut }: { name: string | null; onSignOut: () => void }) {
  const [open, setOpen] = useState(false)
  const router = useRouter()
  return (
    <>
      <Pressable
        onPress={() => { Haptics.selectionAsync(); setOpen(true) }}
        style={({ pressed }) => ({
          width: 42, height: 42, borderRadius: 21, alignItems: 'center', justifyContent: 'center',
          backgroundColor: C.paper, borderWidth: 1, borderColor: HAIRLINE,
          opacity: pressed ? 0.7 : 1, ...CARD_SHADOW,
        })}
      >
        {name ? (
          <Text style={{ fontWeight: F.sansSemi, fontSize: 15, color: C.ink }}>{name[0].toUpperCase()}</Text>
        ) : (
          <AccountIcon />
        )}
      </Pressable>

      <Modal visible={open} transparent animationType="fade" onRequestClose={() => setOpen(false)}>
        <Pressable style={{ flex: 1 }} onPress={() => setOpen(false)} accessibilityLabel="Close menu">
          <Pressable onPress={(e) => e.stopPropagation()} style={{ position: 'absolute', top: 96, right: 20, width: 210, backgroundColor: 'rgba(255,255,255,0.98)', borderWidth: 1, borderColor: 'rgba(0,0,0,0.07)', borderRadius: 16, padding: 14, shadowColor: '#000', shadowOpacity: 0.12, shadowRadius: 28, shadowOffset: { width: 0, height: 8 }, elevation: 8 }}>
            <Pressable
              onPress={() => setOpen(false)}
              hitSlop={10}
              accessibilityRole="button"
              accessibilityLabel="Close"
              style={({ pressed }) => ({ position: 'absolute', top: 8, right: 8, width: 26, height: 26, borderRadius: 13, alignItems: 'center', justifyContent: 'center', opacity: pressed ? 0.5 : 1 })}
            >
              <CloseIcon size={14} color={C.ink2} />
            </Pressable>
            <Text style={{ fontWeight: F.sansMed, fontSize: 11, color: C.ink3, textTransform: 'uppercase', letterSpacing: 1.4, marginBottom: 4 }}>Signed in</Text>
            <Text style={{ fontWeight: F.sansSemi, fontSize: 15, color: C.ink, marginBottom: 12, paddingRight: 22 }}>{name ?? 'Neighbor'}</Text>
            <Pressable
              onPress={() => { Haptics.selectionAsync(); setOpen(false); router.push('/onboarding') }}
              style={({ pressed }) => ({ paddingVertical: 10, borderRadius: 10, borderWidth: 1, borderColor: 'rgba(0,0,0,0.07)', alignItems: 'center', marginBottom: 8, opacity: pressed ? 0.7 : 1 })}
            >
              <Text style={{ fontWeight: F.sansMed, fontSize: 14, color: C.ink }}>Edit interests</Text>
            </Pressable>
            <Pressable
              onPress={() => { setOpen(false); onSignOut() }}
              style={({ pressed }) => ({ paddingVertical: 10, borderRadius: 10, borderWidth: 1, borderColor: 'rgba(0,0,0,0.07)', alignItems: 'center', opacity: pressed ? 0.7 : 1 })}
            >
              <Text style={{ fontWeight: F.sansMed, fontSize: 14, color: C.ink }}>Sign out</Text>
            </Pressable>
          </Pressable>
        </Pressable>
      </Modal>
    </>
  )
}
