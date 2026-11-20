package database

import "testing"

func setupCompletedValue(t *testing.T) (string, bool) {
	t.Helper()
	var value string
	err := DB.QueryRow(`SELECT value FROM app_settings WHERE key = 'setup_completed'`).Scan(&value)
	return value, err == nil
}

// replaySetupMigration rejoue la migration 32 sur la base ouverte, comme une
// installation qui monte de version la joue une seule fois.
func replaySetupMigration(t *testing.T) {
	t.Helper()
	if _, err := DB.Exec(`DELETE FROM app_settings WHERE key = 'setup_completed'`); err != nil {
		t.Fatal(err)
	}
	if _, err := DB.Exec(`DELETE FROM schema_migrations WHERE id = 32`); err != nil {
		t.Fatal(err)
	}
	if err := applyMigrations(DB); err != nil {
		t.Fatalf("applyMigrations: %v", err)
	}
}

// Un serveur déjà installé (au moins une bibliothèque) ne doit jamais voir
// l'assistant du premier lancement (ADR-0164).
func TestAnInstalledServerNeverSeesTheSetupWizard(t *testing.T) {
	openSeedDB(t)
	if _, err := DB.Exec(`INSERT INTO libraries (name, kind, path) VALUES ('Films', 'movies', '/media/Films')`); err != nil {
		t.Fatal(err)
	}

	replaySetupMigration(t)

	if value, ok := setupCompletedValue(t); !ok || value != "true" {
		t.Fatalf("setup_completed = %q (posé : %v), want \"true\" sur un serveur qui a une bibliothèque", value, ok)
	}
}

func TestAFreshServerKeepsTheSetupWizardOpen(t *testing.T) {
	openSeedDB(t)

	if value, ok := setupCompletedValue(t); ok {
		t.Fatalf("setup_completed = %q sur un serveur sans bibliothèque, want absent", value)
	}
	replaySetupMigration(t)
	if value, ok := setupCompletedValue(t); ok {
		t.Fatalf("setup_completed = %q après la migration, want absent", value)
	}
}

// Une installation qui montait de version avec des anciens dossiers : la
// migration des bibliothèques (22) tourne avant la 32, qui les voit.
func TestTheMigrationRunsAfterTheLegacyFoldersBecameLibraries(t *testing.T) {
	var libraries, setup int
	for i, m := range migrations {
		switch m.name {
		case "libraries":
			libraries = i
		case "setup completed for existing servers":
			setup = i
		}
	}
	if libraries == 0 || setup <= libraries {
		t.Fatalf("la migration de l'assistant (rang %d) doit suivre celle des bibliothèques (rang %d)", setup, libraries)
	}
}
