# syntax=docker/dockerfile:1.7

##########################################################################
# Stage 1 — Build
# Uses the Gradle wrapper committed in the repo so the build tool version
# is pinned by the project, not by whatever happens to be on the image.
##########################################################################
FROM eclipse-temurin:21-jdk-jammy AS build

WORKDIR /home/gradle/app

# Leverage Docker layer caching: copy only the files Gradle needs to
# resolve dependencies first, so `./gradlew dependencies` is cached and
# skipped on rebuilds that only change application source.
COPY gradlew ./
COPY gradle ./gradle
COPY build.gradle settings.gradle* ./
RUN chmod +x gradlew && ./gradlew --no-daemon dependencies || true

# Now copy the rest of the source and build the real artifact.
COPY . .
RUN ./gradlew --no-daemon clean build -x test \
    && find /home/gradle/app/build/libs -name '*.jar' ! -name '*-plain.jar' -exec cp {} /home/gradle/app/app.jar \;

##########################################################################
# Stage 2 — Runtime
# JRE-only, non-root, distroless-adjacent base to keep the attack surface
# and image size down (this alone cuts image size roughly in half versus
# shipping the JDK, and removes the compiler toolchain from what ships
# to production).
##########################################################################
FROM eclipse-temurin:21-jre-jammy AS runtime

# Curl is required for the container healthcheck below, calling the
# Spring Boot Actuator /health endpoint added in Part 1.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# Dedicated, unprivileged system user/group — the app never runs as root,
# fixed UID/GID (not just `useradd` defaults) so the same numeric ID is
# predictable and can be pinned in Kubernetes/Container Apps securityContext.
RUN groupadd --gid 1000 spring \
    && useradd --uid 1000 --gid spring --shell /usr/sbin/nologin --create-home spring

WORKDIR /app

COPY --from=build --chown=spring:spring /home/gradle/app/app.jar ./app.jar

USER spring:spring

EXPOSE 4000

# Sensible JVM defaults for a containerised workload: respect cgroup
# memory limits rather than reading host memory, and allow tuning via
# an env var at deploy time without editing the image.
ENV JAVA_OPTS=""

# Container-level healthcheck wired to the DB-aware /health endpoint
# from Part 1, so Compose/orchestrators know the app is not just "up"
# but actually able to reach Postgres.
HEALTHCHECK --interval=15s --timeout=5s --start-period=40s --retries=5 \
    CMD curl --fail http://localhost:4000/health || exit 1

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
