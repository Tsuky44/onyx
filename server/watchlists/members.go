package watchlists

import (
	"fmt"

	"project-player/server/models"
)

// Les invités d'une liste (ADR-0127, ADR-0129) : des comptes du serveur à qui
// le propriétaire donne le droit d'y ajouter et d'y retirer des titres
// (« editor »), ou seulement de la voir, même privée (« viewer »). Ils ne la
// renomment pas, ne la partagent pas, ne la suppriment pas, et n'invitent
// personne : ces droits restent au propriétaire.

// memberColumns projette un compte tel qu'une liste le montre ; il faut
// joindre users sous `u`.
const memberColumns = `u.id, u.username, COALESCE(u.avatar, '')`

func scanMember(row interface{ Scan(...interface{}) error }) (models.WatchListMember, error) {
	var m models.WatchListMember
	err := row.Scan(&m.ID, &m.Username, &m.Avatar)
	return m, err
}

// members renvoie les invités d'une liste, avec leur rôle, du plus ancien au
// plus récent.
func (s *Store) members(listID int) ([]models.WatchListMember, error) {
	rows, err := s.db.Query(`
		SELECT `+memberColumns+`, m.role
		FROM watch_list_members m JOIN users u ON u.id = m.user_id
		WHERE m.list_id = ?
		ORDER BY m.added_at, u.id`, listID)
	if err != nil {
		return nil, fmt.Errorf("query watch list members: %w", err)
	}
	defer rows.Close()
	out := []models.WatchListMember{}
	for rows.Next() {
		var m models.WatchListMember
		err := rows.Scan(&m.ID, &m.Username, &m.Avatar, &m.Role)
		if err != nil {
			return nil, fmt.Errorf("scan watch list member: %w", err)
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

// People renvoie les autres comptes du serveur, ceux qu'on peut inviter : un
// compte voit déjà le nom des propriétaires des listes partagées, rien de plus
// n'est dit ici que son nom et son image.
func (s *Store) People(viewerID int) ([]models.WatchListMember, error) {
	rows, err := s.db.Query(`
		SELECT `+memberColumns+` FROM users u
		WHERE u.id <> ? ORDER BY u.username COLLATE NOCASE, u.id`, viewerID)
	if err != nil {
		return nil, fmt.Errorf("query people: %w", err)
	}
	defer rows.Close()
	out := []models.WatchListMember{}
	for rows.Next() {
		m, err := scanMember(rows)
		if err != nil {
			return nil, fmt.Errorf("scan person: %w", err)
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

// validRole dit si role est un rôle d'invité connu (ADR-0129).
func validRole(role string) bool {
	return role == models.WatchListRoleEditor || role == models.WatchListRoleViewer
}

// AddMember invite un compte à une liste du propriétaire, à la remplir
// (models.WatchListRoleEditor) ou à la voir (models.WatchListRoleViewer).
// Inviter un invité change son rôle ; l'inviter deux fois au même rôle ne
// change rien. La liste « à regarder plus tard » reste à son propriétaire
// seul, et on ne s'invite pas soi-même.
func (s *Store) AddMember(ownerID, listID, userID int, role string) ([]models.WatchListMember, error) {
	kind, err := s.ownedKind(s.db, ownerID, listID)
	if err != nil {
		return nil, err
	}
	if kind != models.WatchListKindCustom || userID <= 0 || userID == ownerID || !validRole(role) {
		return nil, ErrInvalid
	}
	var exists bool
	if err := s.db.QueryRow(`SELECT EXISTS (SELECT 1 FROM users WHERE id = ?)`, userID).Scan(&exists); err != nil {
		return nil, fmt.Errorf("load user %d: %w", userID, err)
	}
	if !exists {
		return nil, ErrInvalid
	}
	var count int
	var current string
	if err := s.db.QueryRow(`
		SELECT COUNT(*), COALESCE(MAX(CASE WHEN user_id = ? THEN role END), '')
		FROM watch_list_members WHERE list_id = ?`, userID, listID).Scan(&count, &current); err != nil {
		return nil, fmt.Errorf("count watch list members: %w", err)
	}
	if current == role {
		return s.members(listID)
	}
	now := s.nowMillis()
	if current == "" {
		if count >= MaxMembersPerList {
			return nil, ErrTooMany
		}
		if _, err := s.db.Exec(`
			INSERT OR IGNORE INTO watch_list_members (list_id, user_id, added_at, role) VALUES (?, ?, ?, ?)`,
			listID, userID, now, role); err != nil {
			return nil, fmt.Errorf("insert watch list member: %w", err)
		}
	} else if _, err := s.db.Exec(`
		UPDATE watch_list_members SET role = ? WHERE list_id = ? AND user_id = ?`,
		role, listID, userID); err != nil {
		return nil, fmt.Errorf("update watch list member role: %w", err)
	}
	if _, err := s.db.Exec(`UPDATE watch_lists SET updated_at = ? WHERE id = ?`, now, listID); err != nil {
		return nil, fmt.Errorf("touch watch list: %w", err)
	}
	return s.members(listID)
}

// RemoveMember retire un invité. Le propriétaire retire qui il veut ; un
// invité ne retire que lui-même, c'est-à-dire qu'il quitte la liste.
func (s *Store) RemoveMember(actorID, listID, userID int) error {
	a, err := s.access(s.db, actorID, listID)
	if err != nil {
		return err
	}
	switch {
	case a.owner:
	case a.member() && actorID == userID:
	case a.visible():
		return ErrNotOwner
	default:
		return ErrNotFound
	}
	res, err := s.db.Exec(`DELETE FROM watch_list_members WHERE list_id = ? AND user_id = ?`, listID, userID)
	if err != nil {
		return fmt.Errorf("delete watch list member: %w", err)
	}
	if n, err := res.RowsAffected(); err != nil {
		return fmt.Errorf("delete watch list member: %w", err)
	} else if n == 0 {
		return ErrNotFound
	}
	return nil
}
