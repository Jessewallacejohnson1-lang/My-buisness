#!/usr/bin/env bash
# UserPromptSubmit hook — when the user mentions or requests animation, remind
# Claude to use the installed gsap-* skills before responding. Standing
# instruction from the user ("whenever I mention animations, use this skill").
#
# Reads the hook JSON on stdin; emits additionalContext only when the prompt
# matches an animation trigger. Always exits 0 (never blocks a prompt).

input="$(cat)"
prompt="$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null)"

# Stems (no word boundaries) so "animation"/"animated"/"animating" all match.
# Case-insensitive. Includes GSAP terms and "reanimated" (the native stack).
if printf '%s' "$prompt" | grep -iqE 'animat|gsap|tween|scroll[ -]?trigger|parallax|keyframe|easing|reanimated|micro[ -]?interaction'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext: "The user mentioned animation. Per their standing instruction, invoke the relevant installed GSAP skill(s) before responding — gsap-core (tweens/easing/reduced-motion), gsap-timeline (sequencing), gsap-scrolltrigger (scroll/parallax/pinning), gsap-plugins, gsap-utils, gsap-react, gsap-frameworks, gsap-performance. This app is Expo / React Native + react-native-reanimated: GSAP runs on the web build (DOM); on native there is no DOM, so translate GSAP patterns into Reanimated. Keep motion on-brand — it confirms, never decorates, and must respect prefers-reduced-motion."
    }
  }'
fi
exit 0
