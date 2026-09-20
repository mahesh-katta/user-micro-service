# syntax=docker/dockerfile:1

###############################################################################
# Stage 1 — build
#
# Dependencies are resolved in their own layer so that a source-only change
# does not re-download the world. Tests are deliberately NOT run here: the
# integration tests use Testcontainers, which needs a Docker daemon that is not
# available inside a build container. CI runs `mvn verify` as a separate job
# before this image is ever built.
###############################################################################
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /build

COPY pom.xml .
RUN --mount=type=cache,target=/root/.m2 \
    mvn -B -q dependency:go-offline

COPY src ./src
RUN --mount=type=cache,target=/root/.m2 \
    mvn -B -q clean package -DskipTests

###############################################################################
# Stage 2 — split the fat jar into layers
#
# Dependencies change rarely, application classes change every commit. Splitting
# them means a redeploy ships a few hundred KB instead of ~60 MB, which is what
# makes ECR pushes and EC2 pulls fast.
###############################################################################
FROM eclipse-temurin:21-jre-alpine AS extract
WORKDIR /staging
COPY --from=build /build/target/*.jar app.jar

# The destination must not be an existing non-empty directory, so the jar is
# staged elsewhere and /extract is created by the extraction itself.
RUN java -Djarmode=tools -jar app.jar extract --layers --launcher --destination /extract

# Layer directories come from the jar's layers.idx, and a layer with no content
# is simply absent - snapshot-dependencies is empty for a release build. COPY
# fails on a missing source, so guarantee all four exist.
RUN mkdir -p /extract/dependencies \
             /extract/spring-boot-loader \
             /extract/snapshot-dependencies \
             /extract/application

###############################################################################
# Stage 3 — runtime
###############################################################################
FROM eclipse-temurin:21-jre-alpine AS runtime

LABEL org.opencontainers.image.title="user-service" \
      org.opencontainers.image.description="JWT authentication and user-management microservice" \
      org.opencontainers.image.source="https://github.com/mahesh-katta/user-micro-service" \
      org.opencontainers.image.licenses="MIT"

# Run as an unprivileged user. A container that is root inside is one kernel
# escape away from being root on the host.
RUN addgroup -S spring && adduser -S spring -G spring

WORKDIR /app

# Copy in layer order: least volatile first, so Docker reuses the lower layers.
COPY --from=extract --chown=spring:spring /extract/dependencies/ ./
COPY --from=extract --chown=spring:spring /extract/spring-boot-loader/ ./
COPY --from=extract --chown=spring:spring /extract/snapshot-dependencies/ ./
COPY --from=extract --chown=spring:spring /extract/application/ ./

USER spring:spring

EXPOSE 8080

# MaxRAMPercentage makes the JVM respect the container's cgroup memory limit
# instead of the host's RAM — the single most common cause of OOM-killed Java
# containers on a t3.micro. SerialGC is the right choice for a small heap.
ENV JAVA_OPTS="-XX:MaxRAMPercentage=75.0 \
-XX:InitialRAMPercentage=50.0 \
-XX:+UseSerialGC \
-XX:+ExitOnOutOfMemoryError \
-Djava.security.egd=file:/dev/./urandom"

HEALTHCHECK --interval=30s --timeout=3s --start-period=45s --retries=3 \
    CMD wget -qO- http://127.0.0.1:8080/actuator/health | grep -q '"status":"UP"' || exit 1

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS org.springframework.boot.loader.launch.JarLauncher"]
