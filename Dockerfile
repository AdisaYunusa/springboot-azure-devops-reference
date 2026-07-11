# syntax=docker/dockerfile:1

###############################################################################
# Stage 1: Build the application using Java 21 on Ubuntu 26.04 LTS.
#
# The project requires Java 21 through the Gradle toolchain configured in
# build.gradle. The repository's Gradle Wrapper is used so the Gradle version
# remains controlled by the project rather than by the container image.
###############################################################################
FROM eclipse-temurin:21-jdk-resolute AS build

WORKDIR /workspace

# Copy the Gradle Wrapper and build configuration before the application source.
# This allows Docker to reuse the dependency-resolution layer when only source
# files change, improving repeat build times.
COPY gradlew ./
COPY gradle ./gradle
COPY build.gradle ./

# The HMCTS Gradle plugin references configuration files such as the OWASP
# Dependency Check suppression file during project configuration.
COPY config ./config

# Ensure the Gradle Wrapper uses Unix line endings and is executable.
RUN sed -i 's/\r$//' ./gradlew \
    && chmod +x ./gradlew

# Use a BuildKit cache mount so downloaded Gradle dependencies can be reused
# across image builds. Dependency failures are intentionally not suppressed.
RUN --mount=type=cache,target=/root/.gradle \
    ./gradlew --no-daemon dependencies

# Copy application source only after dependency resolution, preserving the
# cached dependency layer when application code changes.
COPY src ./src

# CI runs the complete test suite, Checkstyle and other quality gates.
# The image-build stage is responsible only for producing the executable JAR.
RUN --mount=type=cache,target=/root/.gradle \
    ./gradlew --no-daemon bootJar


###############################################################################
# Stage 2: Run the application using Java 21 on Ubuntu 26.04 LTS.
#
# The final image contains only the Java runtime and built application.
# Gradle, source code and the Java compiler remain in the build stage, reducing
# the production image size and attack surface.
###############################################################################
FROM eclipse-temurin:21-jre-resolute AS runtime

# curl is installed solely for the container health check against the Spring
# Boot Actuator endpoint. Package metadata is removed from the same layer.
RUN apt-get update \
    && apt-get install --yes --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# Create a predictable, unprivileged runtime identity. A writable home directory
# is provided separately from /app, while the application files remain
# root-owned and read-only to the runtime process.
RUN groupadd --gid 10001 appgroup \
    && useradd \
        --uid 10001 \
        --gid appgroup \
        --create-home \
        --home-dir /home/appuser \
        --shell /usr/sbin/nologin \
        appuser

WORKDIR /app

# build.gradle explicitly pins bootJar.archiveFileName to test-backend.jar.
# Using the exact filename keeps artifact selection deterministic and avoids
# accidentally copying another JAR if additional artifacts are produced later.
COPY --from=build \
    /workspace/build/libs/test-backend.jar \
    /app/app.jar

# Optional JVM settings can be supplied at deployment time without introducing
# a shell-based entrypoint, for example:
# JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75.0"
ENV JAVA_TOOL_OPTIONS=""

# Run the application as the unprivileged identity created above.
USER appuser:appgroup

# Documents the port used by the Spring Boot service. Port publication is
# configured separately through Docker Compose or the deployment platform.
EXPOSE 4000

# The health endpoint includes the database health indicator, allowing Docker
# and orchestrators to determine whether the application can reach PostgreSQL,
# rather than checking only whether the Java process is running.
HEALTHCHECK --interval=15s \
            --timeout=5s \
            --start-period=40s \
            --retries=5 \
    CMD curl --fail --silent --show-error http://localhost:${SERVER_PORT:-4000}/health || exit 1

# Exec form keeps Java as PID 1 so SIGTERM is delivered directly to Spring Boot,
# allowing the application's configured graceful shutdown behaviour to run.
ENTRYPOINT ["java", "-jar", "/app/app.jar"]