import { cn } from '@/lib/utils';
import { View } from 'react-native';

function Skeleton({
  className,
  ...props
}: React.ComponentProps<typeof View> & React.RefAttributes<View>) {
  // Loading placeholder — paper-100 block on the md12 radius. `animate-pulse`
  // confirms "still loading" on web; static on native (calm by default).
  return <View className={cn('bg-accent animate-pulse rounded-md12', className)} {...props} />;
}

export { Skeleton };
