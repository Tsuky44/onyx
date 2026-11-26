import 'retro_card_slide.dart';
import 'retro_hour_slide.dart';
import 'retro_hours_slide.dart';
import 'retro_moments_slide.dart';
import 'retro_months_slide.dart';
import 'retro_opening_slide.dart';
import 'retro_server_slide.dart';
import 'retro_slide.dart';
import 'retro_top_five_slide.dart';
import 'retro_top_title_slide.dart';

/// Les écrans du Rétro, dans l'ordre du récit : de qui l'on parle, combien,
/// quoi, quand, avec qui, et ce que ça dit de soi.
const List<RetroSlide> kRetroSlides = [
  RetroOpeningSlide(),
  RetroHoursSlide(),
  RetroTopTitleSlide(),
  RetroTopFiveSlide(),
  RetroHourSlide(),
  RetroMonthsSlide(),
  RetroMomentsSlide(),
  RetroServerSlide(),
  RetroCardSlide(),
];
