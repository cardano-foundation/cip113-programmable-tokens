/** @type {import('next').NextConfig} */
const nextConfig = {
  webpack: (config, { isServer }) => {
    config.experiments = {
      ...config.experiments,
      asyncWebAssembly: true,
      layers: true,
    };

    // Set output target to support async/await for WebAssembly
    config.output.environment = {
      ...config.output.environment,
      asyncFunction: true,
    };

    config.resolve.fallback = {
      ...config.resolve.fallback,
      fs: false,
      net: false,
      tls: false,
    };

    return config;
  },
  // Disable strict mode to prevent double renders affecting WASM loading
  reactStrictMode: false,
};

module.exports = nextConfig;
