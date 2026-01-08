// Web customization config file
export const config = {
  // Page title
  pageTitle: 'OwO Network - Looking Glass',
  
  // Footer right text content
  footerRightText: '© 2026 OwO Network, LLC.',
  
  // Web icon path, please put image files in public/images directory
  faviconPath: 'https://owo.network/favicon.ico',
  
  // Web top-left logo path, please put image files in public/images directory
  logoPath: '/images/owo-logo.svg',
  
  // Web background color
  backgroundColor: '#f5f5f5ff'
};

// Export type definition for TypeScript type checking
export type ConfigType = typeof config;