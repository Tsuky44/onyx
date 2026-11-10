package indexer

import (
	"database/sql"
	"errors"
	"fmt"
	"io/fs"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"project-player/server/database"
	"project-player/server/libraries"
	"project-player/server/models"
	"project-player/server/streamcache"
	"project-player/server/subtitles"
)

// Supprimer un média du disque, comme le fait le nettoyage du stockage de
// MediaHub avec Emby (ADR-0114) : les fichiers vidéo partent, puis le dossier
// qui ne contient plus aucune vidéo (affiches, .nfo, sous-titres à côté), puis
// les lignes du catalogue. Le moniteur l'aurait vu tout seul, mais plus tard :
// MediaHub relit la liste juste après.

var (
	// ErrMediaNotFound : aucun film, série, saison ni épisode sous cet id.
	ErrMediaNotFound = errors.New("indexer: media not found")
	// ErrOutsideLibrary : un fichier du média n'est sous aucune bibliothèque
	// de films ou de séries. On ne supprime que ce qu'Onyx a indexé là.
	ErrOutsideLibrary = errors.New("indexer: file outside of movie and show libraries")
)

// DeleteReport dit ce que DeleteMedia a retiré.
type DeleteReport struct {
	FilesRemoved int   `json:"files_removed"`
	BytesFreed   int64 `json:"bytes_freed"`
}

type deletableFile struct {
	id   int
	path string
	size int64
}

// DeleteMedia supprime du disque et du catalogue le film, la série, la saison
// ou l'épisode id. Un fichier déjà absent (Radarr ou Sonarr viennent de le
// supprimer) compte comme supprimé. Si un fichier résiste, ceux qui sont partis
// quittent le catalogue et l'erreur le dit : rien ne reste indexé sans fichier.
func DeleteMedia(id int) (DeleteReport, error) {
	scanRun.Lock()
	defer scanRun.Unlock()

	var mediaType string
	err := database.DB.QueryRow(`SELECT type FROM medias WHERE id = ?`, id).Scan(&mediaType)
	if errors.Is(err, sql.ErrNoRows) {
		return DeleteReport{}, ErrMediaNotFound
	}
	if err != nil {
		return DeleteReport{}, fmt.Errorf("delete media %d: %w", id, err)
	}

	files, err := deletableFilesOf(id, models.MediaType(mediaType))
	if err != nil {
		return DeleteReport{}, err
	}
	roots := libraries.Paths(append(
		libraries.OfKind(libraries.Current(), libraries.KindMovies),
		libraries.OfKind(libraries.Current(), libraries.KindShows)...,
	))
	for _, f := range files {
		if rootOf(f.path, roots) == "" {
			return DeleteReport{}, fmt.Errorf("delete media %d: %s: %w", id, f.path, ErrOutsideLibrary)
		}
	}

	var report DeleteReport
	var failed []string
	removedIDs := make([]int, 0, len(files))
	dirs := map[string]string{}
	for _, f := range files {
		if err := os.Remove(f.path); err != nil && !os.IsNotExist(err) {
			log.Printf("Indexer: cannot delete %s: %v", f.path, err)
			failed = append(failed, filepath.Base(f.path))
			continue
		}
		report.FilesRemoved++
		report.BytesFreed += f.size
		removedIDs = append(removedIDs, f.id)
		dirs[filepath.Dir(f.path)] = rootOf(f.path, roots)
	}
	for dir, root := range dirs {
		pruneEmptyMediaDir(dir, root)
	}

	forgetDeletedMedia(removedIDs)
	if len(failed) == 0 && mediaType != string(models.TypeMovie) && mediaType != string(models.TypeEpisode) {
		// Saison ou série : sa ligne part avec ses enfants (ON DELETE CASCADE).
		if _, err := database.DB.Exec(`DELETE FROM medias WHERE id = ?`, id); err != nil {
			log.Printf("Indexer: cannot forget media %d: %v", id, err)
		}
		clearExtractedSubtitles(id)
	}
	cleanEmptySeasonsAndShows()

	if len(failed) > 0 {
		return report, fmt.Errorf("delete media %d: %d file(s) not removed (%s)", id, len(failed), strings.Join(failed, ", "))
	}
	log.Printf("Indexer: deleted media %d (%s), %d file(s), %d bytes", id, mediaType, report.FilesRemoved, report.BytesFreed)
	return report, nil
}

// deletableFilesOf rend les fichiers vidéo indexés sous un média. Un épisode
// peut pendre directement à sa série (sans saison) : la requête le prend aussi.
func deletableFilesOf(id int, mediaType models.MediaType) ([]deletableFile, error) {
	var query string
	switch mediaType {
	case models.TypeMovie, models.TypeEpisode:
		query = `SELECT id, file_path, COALESCE(file_size, 0) FROM medias WHERE id = ?`
	case models.TypeSeason:
		query = `SELECT id, file_path, COALESCE(file_size, 0) FROM medias WHERE type = 'episode' AND parent_id = ?`
	case models.TypeShow:
		query = `SELECT id, file_path, COALESCE(file_size, 0) FROM medias WHERE type = 'episode'
			AND (parent_id = ?1 OR parent_id IN (SELECT id FROM medias WHERE type = 'season' AND parent_id = ?1))`
	default:
		return nil, ErrMediaNotFound
	}
	rows, err := database.DB.Query(query, id)
	if err != nil {
		return nil, fmt.Errorf("delete media %d: list files: %w", id, err)
	}
	defer rows.Close()
	var files []deletableFile
	for rows.Next() {
		var f deletableFile
		var path sql.NullString
		if err := rows.Scan(&f.id, &path, &f.size); err != nil {
			return nil, fmt.Errorf("delete media %d: scan files: %w", id, err)
		}
		if f.path = strings.TrimSpace(path.String); f.path != "" {
			files = append(files, f)
		}
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("delete media %d: list files: %w", id, err)
	}
	return files, nil
}

// rootOf rend la bibliothèque qui contient path (strictement dessous), ou "".
func rootOf(path string, roots []string) string {
	clean := filepath.ToSlash(filepath.Clean(path))
	for _, root := range roots {
		lower, upper := libraries.PathRange(root)
		if clean >= lower && clean < upper {
			return filepath.Clean(root)
		}
	}
	return ""
}

// pruneEmptyMediaDir supprime dir puis ses parents tant qu'ils ne contiennent
// plus aucune vidéo, sans jamais atteindre la racine de la bibliothèque : le
// dossier d'un film part avec ses affiches et son .nfo, celui d'une série
// quand sa dernière saison est partie.
func pruneEmptyMediaDir(dir, root string) {
	root = filepath.Clean(root)
	for dir = filepath.Clean(dir); dir != root && strings.HasPrefix(dir, root+string(filepath.Separator)); dir = filepath.Dir(dir) {
		if dirHoldsVideo(dir) {
			return
		}
		if err := os.RemoveAll(dir); err != nil {
			log.Printf("Indexer: cannot remove folder %s: %v", dir, err)
			return
		}
		forgetDirScanCache(dir, true)
	}
}

// dirHoldsVideo dit si une vidéo reste sous dir. Un dossier illisible compte
// comme plein : dans le doute, on ne supprime rien.
func dirHoldsVideo(dir string) bool {
	found := false
	err := filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			if os.IsNotExist(err) && path == dir {
				return fs.SkipAll
			}
			found = true
			return fs.SkipAll
		}
		if !d.IsDir() && IsVideoFile(path) {
			found = true
			return fs.SkipAll
		}
		return nil
	})
	return found || (err != nil && !os.IsNotExist(err))
}

func forgetDeletedMedia(ids []int) {
	for _, id := range ids {
		if _, err := database.DB.Exec(`DELETE FROM medias WHERE id = ?`, id); err != nil {
			log.Printf("Indexer: cannot forget media %d: %v", id, err)
			continue
		}
		streamcache.Global().Invalidate(id)
		clearExtractedSubtitles(id)
	}
}

// clearExtractedSubtitles retire les .vtt qu'Onyx a extraits pour le média
// (m<id>.<langue>.vtt) : leurs lignes partent en cascade, pas les fichiers.
func clearExtractedSubtitles(id int) {
	matches, err := filepath.Glob(filepath.Join(subtitles.OutputDir(), "m"+strconv.Itoa(id)+".*.vtt"))
	if err != nil {
		return
	}
	for _, f := range matches {
		if err := os.Remove(f); err != nil && !os.IsNotExist(err) {
			log.Printf("Indexer: cannot remove subtitle %s: %v", f, err)
		}
	}
}
