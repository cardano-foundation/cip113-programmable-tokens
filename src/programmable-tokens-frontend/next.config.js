/** @type {import('next').NextConfig} */
const nextConfig = {
  webpack: (config, { isServer }) => {
    config.experiments = {
      ...config.experiments,
      asyncWebAssembly: true,
      layers: true,
    };
    config.resolve.fallback = {
      ...config.resolve.fallback,
      fs: false,
      net: false,
      tls: false,
    };
    // Fix for WebAssembly modules in Mesh SDK
    config.module.rules.push({
      test: /\.wasm$/,
      type: 'webassembly/async',
    });
    // Prevent bundling WASM on server side
    if (isServer) {
      config.externals = [...(config.externals || []), '@meshsdk/core-csl'];
    }
    return config;
  },
  // Disable strict mode to prevent double renders affecting WASM loading
  reactStrictMode: false,
};

module.exports = nextConfig;
