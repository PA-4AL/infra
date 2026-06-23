# Backend Kotlin/Spring Boot — build Gradle puis JRE seule.
# Contexte de build attendu : le repo backend/ (voir infra/docker-compose.yml).
FROM gradle:8-jdk21 AS build
WORKDIR /app
COPY . .
RUN gradle bootJar --no-daemon

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /app/build/libs/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
