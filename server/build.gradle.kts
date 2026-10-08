import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.util.*

plugins {
	java
	id("org.springframework.boot") version "3.4.2"
	id("io.spring.dependency-management") version "1.1.7"
}

group = "br.com.cortaaqui"
version = "0.0.1-SNAPSHOT"

java {
	toolchain {
		languageVersion = JavaLanguageVersion.of(21)
	}
}

repositories {
	mavenCentral()
}

dependencies {
	implementation("org.springframework.boot:spring-boot-starter-web")
	implementation("org.springframework.boot:spring-boot-starter-validation")
	implementation("org.springframework.boot:spring-boot-starter-jdbc")
	implementation("org.springframework.boot:spring-boot-starter-security")
	implementation("org.flywaydb:flyway-core")
	implementation("org.flywaydb:flyway-database-postgresql")

	developmentOnly("org.springframework.boot:spring-boot-devtools")

	runtimeOnly("org.postgresql:postgresql")

	testImplementation("org.springframework.boot:spring-boot-starter-test")
	testImplementation("org.springframework.security:spring-security-test")
	// Postgres de verdade nos testes: usa TEST_DB_URL se existir, senão sobe postgres:17 com Testcontainers.
	testImplementation("org.testcontainers:postgresql")
	testImplementation("org.testcontainers:junit-jupiter")

	testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.withType<Test> {
	useJUnitPlatform()
	// QA: a JVM dos testes roda em UTC; as regras de "dia" e "mês" usam America/Sao_Paulo explicitamente.
	jvmArgs("-Duser.timezone=UTC")
	testLogging {
		events("failed")
		exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
	}
}

tasks.named("build") {
	doLast{
		val trigger = file("src/main/resources/trigger.txt")
		if (!trigger.exists()){
			trigger.createNewFile()
		}
		trigger.writeText(Date().time.toString())
	}
}

tasks.register("generateFlywayMigrationFile"){

	description = "Generate flyway migration"
	group = "Flyway"

	doLast {
		val migrationsDir = file("src/main/resources/db/migration")
		if (!migrationsDir.exists()) {
			migrationsDir.mkdirs()
		}

		val migrationNameFromConsole = project.findProperty("migrationName") as String?
			?: throw IllegalArgumentException("Você deve fornecer um nome para a migração usando o parâmetro -PmigrationName=<nome>.")

		val timestamp = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMddHHmmss"))
		val migrationName = "V${timestamp}__${migrationNameFromConsole}.sql"

		val migrationFile = file("${migrationsDir.path}/$migrationName")
		migrationFile.writeText("-- $migrationName generated in ${migrationsDir.path}")

		logger.lifecycle("Migration file created: ${migrationFile.path}")

	}
}
