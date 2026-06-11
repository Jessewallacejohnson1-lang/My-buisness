type IconProps = React.SVGProps<SVGSVGElement>

function base(props: IconProps): IconProps {
  return {
    viewBox: '0 0 24 24',
    fill: 'none',
    stroke: 'currentColor',
    strokeWidth: 1.5,
    strokeLinecap: 'round',
    strokeLinejoin: 'round',
    'aria-hidden': true,
    ...props,
  }
}

/** Concentric growth rings — the Today / dashboard mark. */
export function IconRings(props: IconProps) {
  return (
    <svg {...base(props)}>
      <circle cx="12" cy="12" r="9" />
      <circle cx="12" cy="12" r="5" opacity="0.55" />
      <circle cx="12" cy="12" r="1.2" fill="currentColor" stroke="none" />
    </svg>
  )
}

export function IconBowl(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M4 12h16a8 8 0 0 1-16 0Z" />
      <path d="M9 12c0-4 1.5-7 5.5-8.5" opacity="0.55" />
    </svg>
  )
}

export function IconBarcode(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M4 7v10M8 7v10M11 7v6M14 7v10M17 7v6M20 7v10" />
    </svg>
  )
}

export function IconDumbbell(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M6.5 6.5v11M17.5 6.5v11M3.5 9v6M20.5 9v6M6.5 12h11" />
    </svg>
  )
}

export function IconFlame(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M12 21c-4 0-6.5-2.6-6.5-6 0-2.5 1.4-4.4 2.7-6C9.4 7.6 10.5 6 10.5 3.5c3 1.5 4 4.5 3.5 6.5 1-.5 1.8-1.3 2-2.5 1.6 1.7 2.5 3.9 2.5 6 0 3.4-2.5 7.5-6.5 7.5Z" />
    </svg>
  )
}

export function IconPlus(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M12 5v14M5 12h14" />
    </svg>
  )
}

export function IconCheck(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M5 12.5l4.5 4.5L19 7.5" />
    </svg>
  )
}

export function IconX(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M6 6l12 12M18 6L6 18" />
    </svg>
  )
}

export function IconChevronDown(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M6 9.5l6 6 6-6" />
    </svg>
  )
}

export function IconSearch(props: IconProps) {
  return (
    <svg {...base(props)}>
      <circle cx="11" cy="11" r="6.5" />
      <path d="M16 16l4.5 4.5" />
    </svg>
  )
}

export function IconLogout(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M14 4H7a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h7" />
      <path d="M17 8l4 4-4 4M21 12H10" />
    </svg>
  )
}

export function IconTrash(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M5 7h14M10 7V5a1 1 0 0 1 1-1h2a1 1 0 0 1 1 1v2M7 7l1 13h8l1-13" />
    </svg>
  )
}

export function IconArrowLeft(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M19 12H5M11 6l-6 6 6 6" />
    </svg>
  )
}

export function IconLeaf(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M19 5c-9 0-14 4-14 10 0 2.5 1.5 4 4 4 6 0 10-5 10-14Z" />
      <path d="M5 19c3-5 7-8 11-10" opacity="0.55" />
    </svg>
  )
}

export function IconAlert(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M12 3.5 2.5 20h19L12 3.5ZM12 10v4.5" />
      <circle cx="12" cy="17.2" r="0.4" fill="currentColor" stroke="none" />
    </svg>
  )
}
