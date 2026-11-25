package capacity

import (
	"fmt"
	"math"
	"time"
)

// La rétroaction : ce que les sessions ont vraiment tenu corrige le profil
// (phase 5 du plan docs/transcodage-adaptatif.md).
//
// Le banc mesure une seconde de source de synthèse sur une machine froide.
// Trois choses le rendent optimiste, et aucune ne se voit au banc :
//
//   - les vrais fichiers sont plus durs que la synthèse (grain, mouvement) ;
//   - une machine qui chauffe ralentit : l'i7 de fytroz à 99 °C ;
//   - le modèle de vitesse suppose qu'une session prend tous les cœurs libres
//     (phase 2). Sur un Xeon à deux sockets, x264 plafonne bien avant, à ses
//     seize threads et au trafic entre nœuds NUMA.
//
// Chaque session rapporte donc sa vitesse réelle et son temps CPU réel, et une
// correction lissée par classe de recette multiplie les coûts prévus. Un seul
// facteur sert à la vitesse prévue et à la réservation du budget : quand les
// deux signaux divergent (un Xeon qui va moins vite sans brûler plus), la
// réservation prend le plus prudent, comme le reste du budget (phase 3).

const (
	// CorrectionAlpha est le poids d'une session dans la moyenne lissée. Un
	// quart : il faut trois ou quatre sessions concordantes pour que la
	// correction fasse l'essentiel du chemin, et une session seule ne la fait
	// pas basculer.
	CorrectionAlpha = 0.25
	// SampleMin et SampleMax bornent ce qu'une session peut dire. Une session
	// aberrante (un fichier cassé dont chaque image fait une erreur, un partage
	// réseau qui cale) donnerait un rapport de 10 ou de 20 ; bornée à 2,5,
	// elle déplace une correction neutre jusqu'à 1,375 au plus. 2,5 couvre
	// l'écart le plus large attendu : le Xeon qui plafonne à seize threads
	// quand le modèle lui en donne trente-deux, sur un fichier plus dur que la
	// synthèse.
	SampleMin = 0.5
	SampleMax = 2.5
	// CorrectionMin et CorrectionMax bornent la correction elle-même. Plus de
	// trois fois le banc, ou moins de la moitié, ce n'est plus corriger : c'est
	// que le banc s'est trompé de machine, et Remeasure est la réponse.
	CorrectionMin = 0.5
	CorrectionMax = 3.0
	// speedRatioCeiling : au-delà de cette vitesse prévue, la vitesse réelle ne
	// dit plus rien du coût. Un 360p prévu à 40× qui sort à 15× bute sur la
	// lecture du fichier ou sur les parties séquentielles de FFmpeg, pas sur
	// les cœurs ; l'admission ne se joue qu'autour de 1 à 1,5×.
	speedRatioCeiling = 4.0
	// minCPUForRatio : sous ce coût prévu (une recette du circuit), le temps
	// CPU réel est dominé par le démarrage et l'audio, et le rapport n'a pas
	// de sens.
	minCPUForRatio = 0.25
)

// Correction est le facteur appris pour une classe de recette.
type Correction struct {
	// Factor multiplie les coûts prévus : 1,4 veut dire que les sessions de
	// cette classe coûtent 40 % de plus que ce que le banc prévoyait.
	Factor  float64   `json:"factor"`
	Samples int       `json:"samples"`
	Updated time.Time `json:"updated"`
}

// CorrectionFor est le facteur de cette classe, 1 sans observation.
func (p *Profile) CorrectionFor(class string) float64 {
	if p == nil {
		return 1
	}
	if c, ok := p.Corrections[class]; ok && c.Factor > 0 {
		return c.Factor
	}
	return 1
}

// Observation est ce qu'une session a vraiment tenu.
type Observation struct {
	// Class est Pipeline.Class.
	Class string
	// Cost et Correction sont ceux de la recette prévue (Pipeline.Cost, déjà
	// multiplié par Pipeline.Correction) : le rapport se fait contre le coût
	// du banc, pour que la moyenne converge au lieu de se corriger elle-même.
	Cost       Cost
	Correction float64
	// Extra est ce que la session coûte en plus de l'image (l'audio).
	Extra Cost
	// Load est la charge des autres sessions pendant la mesure.
	Load Load
	// Speed est la vitesse réelle à plein régime, 0 si elle n'est pas connue.
	Speed float64
	// CPU est le temps CPU réel en cœurs par seconde de film, 0 s'il ne l'est
	// pas.
	CPU float64
	At  time.Time
}

// Ratio est ce que la session dit du coût de sa classe : le rapport entre le
// réel et la prévision du banc, borné. ok est faux quand elle ne dit rien.
func (o Observation) Ratio(p *Profile) (float64, bool) {
	if p == nil || o.Class == "" {
		return 0, false
	}
	correction := o.Correction
	if correction <= 0 {
		correction = 1
	}
	base := o.Cost.Times(1 / correction)
	ratio, ok := 0.0, false
	if o.Speed > 0 {
		predicted := SpeedUnder(base, p, Load{Used: o.Load.Used.Plus(o.Extra)})
		if predicted > 0 && predicted <= speedRatioCeiling {
			ratio, ok = predicted/o.Speed, true
		}
	}
	if o.CPU > 0 && base.CPU >= minCPUForRatio {
		if r := (o.CPU - o.Extra.CPU) / base.CPU; r > 0 {
			ratio, ok = math.Max(ratio, r), true
		}
	}
	if !ok {
		return 0, false
	}
	return math.Min(math.Max(ratio, SampleMin), SampleMax), true
}

// Observe rend un nouveau profil qui tient compte de l'observation, et le
// rapport retenu ; ok est faux quand elle ne dit rien. Le profil publié ne
// change jamais en place, comme pour un retrait (WithTrials).
func (p *Profile) Observe(o Observation) (next *Profile, ratio float64, ok bool) {
	ratio, ok = o.Ratio(p)
	if !ok {
		return p, 0, false
	}
	copied := *p
	copied.Corrections = make(map[string]Correction, len(p.Corrections)+1)
	for class, c := range p.Corrections {
		copied.Corrections[class] = c
	}
	c := copied.Corrections[o.Class]
	if c.Factor <= 0 {
		c.Factor = 1
	}
	c.Factor += CorrectionAlpha * (ratio - c.Factor)
	c.Factor = math.Round(math.Min(math.Max(c.Factor, CorrectionMin), CorrectionMax)*1000) / 1000
	c.Samples++
	c.Updated = o.At.UTC()
	copied.Corrections[o.Class] = c
	return &copied, ratio, true
}

// recipeClass range une recette dans sa classe de correction : ce qui change
// son coût réel sans que le banc le distingue. Le décodage (le circuit ou le
// processeur, et la classe du flux), la hauteur produite (le coût par pixel
// n'est pas linéaire : une 2160p sature autrement qu'une 720p), le tone
// mapping et son périphérique, l'encodeur, et les filtres logiciels que le
// banc ne mesure pas (désentrelacement, sous-titre incrusté).
//
// Le preset n'en fait pas partie : ce qui rend le banc optimiste (un fichier
// plus dur, une machine qui chauffe, des cœurs qu'une session n'occupe pas)
// pèse sur tous les presets d'un encodeur. Une correction par preset
// laisserait le planificateur fuir vers un preset jamais observé, prévu aussi
// faux que celui qu'on vient de corriger.
func recipeClass(pipe Pipeline, heavy bool, outHeight int, softwareOnly bool) string {
	stream := "h264"
	if heavy {
		stream = "hevc10"
	}
	tm := pipe.ToneMap
	switch {
	case tm == "":
		tm = "aucun"
	case pipe.ToneMapOnGPU:
		tm += "@gpu"
	}
	class := fmt.Sprintf("%s/%s|%s|%s|%s", stream, pipe.Decode, heightBand(outHeight), tm, pipe.Encoder)
	if softwareOnly {
		class += "|filtres"
	}
	return class
}

// heightBand est la plage de résolution d'une image produite, avec les seuils
// de streaming.nativeTierHeight : un film en scope de 804 lignes est du 1080p.
func heightBand(height int) string {
	switch {
	case height > 1400:
		return "2160p"
	case height > 800:
		return "1080p"
	case height > 560:
		return "720p"
	default:
		return "sd"
	}
}
