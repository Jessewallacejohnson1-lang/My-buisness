import { Text, TextClassContext } from '@/components/ui/text';
import { cn } from '@/lib/utils';
import { CARD_SHADOW } from '@/theme';
import { View } from 'react-native';

// The canonical Hygge card: warm paper surface, hairline border, lg16 corners,
// lifted by CARD_SHADOW — the single elevation in the system (see theme.ts).
// The shadow is applied via `style` (not a className) so the lift is identical
// to the hand-built cards across the screens. Keep this view un-clipped — if you
// need to clip an image to the corner, nest the clipped child, don't add
// `overflow-hidden` here (it would swallow the shadow).
function Card({ className, style, ...props }: React.ComponentProps<typeof View> & React.RefAttributes<View>) {
  return (
    <TextClassContext.Provider value="text-card-foreground">
      <View
        className={cn(
          'bg-card border-border flex flex-col gap-4 rounded-lg16 border py-5',
          className
        )}
        style={[CARD_SHADOW, style]}
        {...props}
      />
    </TextClassContext.Provider>
  );
}

function CardHeader({ className, ...props }: React.ComponentProps<typeof View> & React.RefAttributes<View>) {
  return <View className={cn('flex flex-col gap-1.5 px-5', className)} {...props} />;
}

function CardTitle({
  className,
  ref,
  ...props
}: React.ComponentProps<typeof Text> & React.RefAttributes<typeof Text>) {

  return (
    <Text
      ref={ref}
      role="heading"
      aria-level={3}
      className={cn('font-display-semi leading-none', className)}
      {...props}
    />
  );
}

function CardDescription({
  className,
  ...props
}: React.ComponentProps<typeof Text> & React.RefAttributes<typeof Text>) {
  return <Text className={cn('font-sans text-muted-foreground text-sm', className)} {...props} />;
}

function CardContent({ className, ...props }: React.ComponentProps<typeof View> & React.RefAttributes<View>) {
  return <View className={cn('px-5', className)} {...props} />;
}

function CardFooter({ className, ...props }: React.ComponentProps<typeof View> & React.RefAttributes<View>) {
  return <View className={cn('flex flex-row items-center px-5', className)} {...props} />;
}

export { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle };
