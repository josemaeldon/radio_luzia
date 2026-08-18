import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "br.com.cloudbrapp.radioluzia"
    compileSdk = 35

    val signingProperties = rootProject.file("keystore.properties")
    val loadedSigningProperties = if (signingProperties.exists()) {
        Properties().apply {
            signingProperties.inputStream().use(::load)
        }
    } else {
        null
    }

    signingConfigs {
        create("release") {
            if (loadedSigningProperties != null) {
                storeFile = rootProject.file(loadedSigningProperties.getProperty("MYAPP_UPLOAD_STORE_FILE"))
                storePassword = loadedSigningProperties.getProperty("MYAPP_UPLOAD_STORE_PASSWORD")
                keyAlias = loadedSigningProperties.getProperty("MYAPP_UPLOAD_KEY_ALIAS")
                keyPassword = loadedSigningProperties.getProperty("MYAPP_UPLOAD_KEY_PASSWORD")
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "org.santaluzia.radio"
        minSdk = 26
        targetSdk = 35
        versionCode = 8
        versionName = "3.0"
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
        }
    }
    buildFeatures { compose = true }
    packaging { resources.excludes += "/META-INF/{AL2.0,LGPL2.1}" }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)
    androidTestImplementation(composeBom)
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.activity:activity-compose:1.10.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.media3:media3-exoplayer:1.5.1")
    implementation("androidx.media3:media3-common:1.5.1")
    implementation("androidx.media3:media3-session:1.5.1")
    implementation("androidx.media:media:1.7.0")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    debugImplementation("androidx.compose.ui:ui-tooling")
}
