package com.maheshreddy.userservice;

import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.test.context.ActiveProfiles;
import org.testcontainers.postgresql.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * Boots the full application against a real PostgreSQL instance started by Testcontainers.
 * Flyway runs its migrations against that database, then Hibernate validates the schema,
 * so a migration that drifts from the entity model fails the build rather than production.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.MOCK)
@ActiveProfiles("test")
@Testcontainers
public abstract class AbstractIntegrationTest {

    @Container
    @ServiceConnection
    static final PostgreSQLContainer POSTGRES = new PostgreSQLContainer("postgres:16-alpine");
}
