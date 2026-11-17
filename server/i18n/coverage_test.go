package i18n

import (
	"go/ast"
	"go/parser"
	"go/token"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"testing"
)

// sinks dit, pour chaque fonction qui rend un message à l'app ou le marque
// pour la traduction, la position de son argument « phrase française ».
var sinks = map[string]int{
	"writeJSONError":     2,
	"writeMediaHubError": 2,
	"i18n.T":             1,
	"i18n.Respond":       1,
	"i18n.Key":           0,
	"i18n.Errorf":        0,
}

// codeKey reconnaît un code de protocole (« link_unknown ») : il se lit par
// l'autre serveur Onyx, pas par une personne, et ne se traduit pas.
var codeKey = regexp.MustCompile(`^[a-z][a-z_]*$`)

type finding struct {
	pos string
	key string
	bad string // non vide : forme interdite, avec la raison
}

func calleeName(fn ast.Expr) string {
	switch f := fn.(type) {
	case *ast.Ident:
		return f.Name
	case *ast.SelectorExpr:
		if x, ok := f.X.(*ast.Ident); ok {
			return x.Name + "." + f.Sel.Name
		}
	}
	return ""
}

func stringLit(e ast.Expr) (string, bool) {
	lit, ok := e.(*ast.BasicLit)
	if !ok || lit.Kind != token.STRING {
		return "", false
	}
	s, err := strconv.Unquote(lit.Value)
	return s, err == nil
}

// foldString lit une phrase que le compilateur sait déjà : un littéral, une
// constante, ou des littéraux collés par + pour tenir en largeur.
func foldString(e ast.Expr, consts map[string]string) (string, bool) {
	switch x := e.(type) {
	case *ast.BasicLit:
		return stringLit(x)
	case *ast.Ident:
		s, ok := consts[x.Name]
		return s, ok
	case *ast.ParenExpr:
		return foldString(x.X, consts)
	case *ast.BinaryExpr:
		if x.Op != token.ADD {
			return "", false
		}
		l, ok := foldString(x.X, consts)
		if !ok {
			return "", false
		}
		r, ok := foldString(x.Y, consts)
		return l + r, ok
	}
	return "", false
}

// scanServer lit toutes les sources non-test de server/ et rend chaque phrase
// qui part vers l'app.
func scanServer(t *testing.T) []finding {
	t.Helper()
	fset := token.NewFileSet()
	byDir := map[string][]*ast.File{}
	err := filepath.WalkDir("..", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			switch d.Name() {
			case "data", "downloads", "node_modules":
				return filepath.SkipDir
			}
			return nil
		}
		if !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
			return nil
		}
		f, err := parser.ParseFile(fset, path, nil, parser.SkipObjectResolution)
		if err != nil {
			return err
		}
		dir := filepath.Dir(path)
		byDir[dir] = append(byDir[dir], f)
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}

	var out []finding
	for _, files := range byDir {
		consts := map[string]string{}
		for _, f := range files {
			for _, decl := range f.Decls {
				gd, ok := decl.(*ast.GenDecl)
				if !ok || gd.Tok != token.CONST {
					continue
				}
				for _, spec := range gd.Specs {
					vs := spec.(*ast.ValueSpec)
					for i, name := range vs.Names {
						if i < len(vs.Values) {
							if s, ok := stringLit(vs.Values[i]); ok {
								consts[name.Name] = s
							}
						}
					}
				}
			}
		}
		for _, f := range files {
			ast.Inspect(f, func(n ast.Node) bool {
				call, ok := n.(*ast.CallExpr)
				if !ok {
					return true
				}
				idx, ok := sinks[calleeName(call.Fun)]
				if !ok || idx >= len(call.Args) {
					return true
				}
				arg := call.Args[idx]
				pos := fset.Position(arg.Pos()).String()
				if s, ok := foldString(arg, consts); ok {
					out = append(out, finding{pos: pos, key: s})
					return true
				}
				switch a := arg.(type) {
				case *ast.Ident:
					// Une variable reçoit sa phrase d'un i18n.Key, lu à part.
				case *ast.BinaryExpr:
					out = append(out, finding{pos: pos, bad: "phrase construite par concaténation : écris la phrase entière avec {0}"})
				case *ast.CallExpr:
					switch name := calleeName(a.Fun); {
					case name == "fmt.Sprintf" || name == "fmt.Sprint" || name == "fmt.Errorf":
						out = append(out, finding{pos: pos, bad: "phrase construite par " + name + " : écris la phrase entière avec {0}"})
					case strings.HasPrefix(name, "i18n."):
						// déjà marquée ou traduite
					default:
						out = append(out, finding{pos: pos, bad: "message rendu par " + name + "(…) : écris une phrase traduite et passe la valeur brute en argument ({0})"})
					}
				}
				return true
			})
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].pos < out[j].pos })
	return out
}

// TestEveryServerMessageHasItsEnglishEntry est le garde-fou de l'ADR-0137 :
// un message écrit en français et envoyé à l'app doit avoir sa traduction
// dans chaque dictionnaire, sinon une personne qui a réglé l'app en anglais
// lit du français au milieu d'une erreur.
func TestEveryServerMessageHasItsEnglishEntry(t *testing.T) {
	found := scanServer(t)
	keys := map[string]bool{}
	for _, f := range found {
		if f.bad != "" {
			t.Errorf("%s: %s", f.pos, f.bad)
			continue
		}
		if codeKey.MatchString(f.key) {
			continue
		}
		keys[f.key] = true
	}
	if path := os.Getenv("ONYX_DUMP_I18N_KEYS"); path != "" {
		var list []string
		for k := range keys {
			list = append(list, k)
		}
		sort.Strings(list)
		if err := os.WriteFile(path, []byte(strings.Join(list, "\n")+"\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	for code, dict := range dictionaries {
		for k := range keys {
			if _, ok := dict[k]; !ok {
				t.Errorf("[%s] traduction manquante : %q", code, k)
			}
		}
		// Une entrée qui ne correspond plus à aucun message est une traduction
		// morte : la phrase française a changé, l'anglais est resté.
		for k := range dict {
			if !keys[k] {
				t.Errorf("[%s] entrée sans message correspondant dans le code : %q", code, k)
			}
		}
	}
}
