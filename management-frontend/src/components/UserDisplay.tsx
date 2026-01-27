import { Box, Avatar, Typography, Tooltip } from '@mui/material';
import type { User } from '../types';

interface UserDisplayProps {
  user?: User | null;
  showName?: boolean;
  size?: 'small' | 'medium' | 'large';
  variant?: 'circular' | 'rounded' | 'square';
}

export default function UserDisplay({
  user,
  showName = true,
  size = 'medium',
  variant = 'circular',
}: UserDisplayProps) {
  const getSize = () => {
    switch (size) {
      case 'small':
        return 24;
      case 'large':
        return 48;
      default:
        return 32;
    }
  };

  const getFontSize = () => {
    switch (size) {
      case 'small':
        return '0.75rem';
      case 'large':
        return '1.25rem';
      default:
        return '0.875rem';
    }
  };

  if (!user) {
    return (
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
        <Avatar
          variant={variant}
          sx={{
            width: getSize(),
            height: getSize(),
            bgcolor: 'grey.400',
            fontSize: getFontSize(),
          }}
        >
          ?
        </Avatar>
        {showName && (
          <Typography variant="body2" color="text.secondary">
            System
          </Typography>
        )}
      </Box>
    );
  }

  const displayName = `${user.first_name} ${user.last_name}`.trim() || user.username || 'Unknown';
  const initials = user.first_name && user.last_name
    ? `${user.first_name[0]}${user.last_name[0]}`
    : user.username?.[0]?.toUpperCase() || '?';

  const avatarContent = user.icon_url ? (
    <Avatar
      src={user.icon_url}
      alt={displayName}
      variant={variant}
      sx={{
        width: getSize(),
        height: getSize(),
        bgcolor: 'primary.main',
      }}
    />
  ) : (
    <Avatar
      variant={variant}
      sx={{
        width: getSize(),
        height: getSize(),
        bgcolor: 'primary.main',
        fontSize: getFontSize(),
      }}
    >
      {initials}
    </Avatar>
  );

  const content = (
    <Box sx={{ display: 'inline-flex', alignItems: 'center', gap: 1 }}>
      {avatarContent}
      {showName && (
        <Typography variant="body2" component="span">
          {displayName}
        </Typography>
      )}
    </Box>
  );

  if (showName) {
    return content;
  }

  return (
    <Tooltip title={displayName}>
      {content}
    </Tooltip>
  );
}

