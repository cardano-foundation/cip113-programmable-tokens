package org.cardanofoundation.cip113.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.EnableWebMvc;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * Web MVC Configuration for CORS and HTTP settings.
 *
 * <p>Configures Cross-Origin Resource Sharing (CORS) to allow the frontend
 * application to communicate with this API service. In production, the
 * allowed origins should be restricted to specific domains.</p>
 *
 * <h2>CORS Settings</h2>
 * <ul>
 *   <li><b>Origins:</b> All origins allowed (development mode)</li>
 *   <li><b>Methods:</b> GET, POST, PUT, DELETE, PATCH</li>
 *   <li><b>Credentials:</b> Allowed for wallet session tokens</li>
 *   <li><b>Max Age:</b> 3600 seconds (1 hour)</li>
 * </ul>
 *
 * @see org.springframework.web.servlet.config.annotation.WebMvcConfigurer
 */
@Configuration
@EnableWebMvc
public class WebConfig implements WebMvcConfigurer {

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/**")
                .allowedOriginPatterns("*")
                .allowedMethods("GET", "POST", "PUT", "DELETE", "PATCH")
                .allowCredentials(true)
                .maxAge(3600);
    }

}
