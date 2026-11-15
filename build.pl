#!/usr/bin/perl
# Builds the static site, one copy per language:
#   docs/<lang>/index.html            the top page
#   docs/<lang>/<page>/index.html     detail pages (destinations, seasons, routes, culture, travel basics)
#
#   Source:  src/template.html      top page, with Japanese text and data-i18n keys
#            src/i18n.json          top-page translations for the other languages
#            src/place.html         detail-page layout, with {{placeholders}}
#            src/places.json        destination pages: text for every language, and official links
#            src/pages.json         the other detail pages: which top-page text and links each one uses
#            src/pages/<lang>.json  the other detail pages: longer text, one file per language
#   Output:  docs/                  the folder GitHub Pages serves
#
# Usage, from Git Bash in this folder:
#   perl build.pl                                  # relative links (local preview)
#   perl build.pl https://USER.github.io/REPO      # absolute links + sitemap (for publishing)
use strict;
use warnings;
use utf8;
use JSON::PP;
use File::Path qw(make_path);
use File::Basename qw(dirname);

my $base = shift // '';
$base =~ s{/+$}{};
my $dir = dirname(__FILE__);

# [ language code, folder name, Open Graph locale ]
my @langs = (
  ['ja',      'ja',      'ja_JP'],
  ['en',      'en',      'en_US'],
  ['zh-Hans', 'zh-hans', 'zh_CN'],
  ['zh-Hant', 'zh-hant', 'zh_TW'],
  ['fr',      'fr',      'fr_FR'],
  ['es',      'es',      'es_ES'],
);

sub slurp {
  my ($path, $layer) = @_;
  open my $fh, "<$layer", $path or die "Cannot read $path: $!";
  local $/;
  return <$fh>;
}
sub spit {
  my ($path, $text) = @_;
  make_path(dirname($path));
  open my $fh, '>:raw:encoding(UTF-8)', $path or die "Cannot write $path: $!";
  print $fh $text;
  close $fh;
}
sub esc {
  my $s = shift;
  $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g;
  return $s;
}
sub json_file { JSON::PP->new->utf8->decode(slurp("$dir/src/$_[0]", ':raw')) }

my $tpl       = slurp("$dir/src/template.html", ':encoding(UTF-8)');
my $place_tpl = slurp("$dir/src/place.html", ':encoding(UTF-8)');
my $dict      = json_file('i18n.json');
my $pdata     = json_file('places.json');
my $odata     = json_file('pages.json');
my @places    = @{ $pdata->{places} };
my @others    = @{ $odata->{pages} };

# $depth = how many folders below docs/ the page sits (1 = top page, 2 = detail page)
sub page_url {
  my ($slug, $page, $depth) = @_;
  return $base ne '' ? "$base/$slug/$page" : ('../' x $depth) . "$slug/$page";
}

# Text of a top-page data-i18n key, as plain text: Japanese from the template, the rest from i18n.json
sub label {
  my ($key, $code) = @_;
  if ($code eq 'ja') {
    my ($v) = $tpl =~ m{\sdata-i18n="\Q$key\E"[^>]*>(.*?)<}s;
    defined $v or die "No data-i18n=\"$key\" in src/template.html";
    return $v;
  }
  my $v = $dict->{$code}{$key};
  defined $v or die "Missing translation: $code / $key";
  return $v;
}

# Replaces data-i18n text with the translation for the language, and fills in the <head>.
sub localize {
  my ($html, $l, $page, $depth, $image) = @_;
  my ($code, $slug, $locale) = @$l;
  my $d = $code eq 'ja' ? undef : ($dict->{$code} or die "No translations for $code");
  my $tr = sub {
    my ($key, $original) = @_;
    return $original unless $d;
    defined $d->{$key} or die "Missing translation: $code / $key";
    return esc($d->{$key});
  };

  # Element text:  <tag data-i18n="key">text</tag>
  $html =~ s{(<(\w+)\b[^>]*?)\s+data-i18n="([^"]+)"([^>]*>)(.*?)(</\2>)}{$1 . $4 . $tr->($3, $5) . $6}gse;
  # Attribute text:  <meta data-i18n-content="key" content="text">
  $html =~ s{\s+data-i18n-content="([^"]+)"(\s+content=")([^"]*)(")}{$2 . $tr->($1, $3) . $4}gse;

  $html =~ s{<html lang="[^"]*"}{<html lang="$code"};
  $html =~ s{<option value="\Q$code\E">}{<option value="$code" selected>};

  my ($title) = $html =~ m{<title>(.*?)</title>}s;
  my ($desc)  = $html =~ m{<meta name="description" content="([^"]*)"};
  my $root_url = $base ne '' ? "$base/" : '../' x $depth;

  my @head;
  push @head, qq{<link rel="canonical" href="} . page_url($slug, $page, $depth) . qq{">};
  push @head, qq{<link rel="alternate" hreflang="$_->[0]" href="} . page_url($_->[1], $page, $depth) . qq{">} for @langs;
  push @head, qq{<link rel="alternate" hreflang="x-default" href="} . ($page eq '' ? $root_url : page_url('en', $page, $depth)) . qq{">};
  push @head, qq{<meta property="og:type" content="website">};
  push @head, qq{<meta property="og:site_name" content="DISCOVERIES">};
  push @head, qq{<meta property="og:title" content="$title">};
  push @head, qq{<meta property="og:description" content="$desc">};
  push @head, qq{<meta property="og:locale" content="$locale">};
  if ($base ne '') {
    push @head, qq{<meta property="og:url" content="} . page_url($slug, $page, $depth) . qq{">};
    push @head, qq{<meta property="og:image" content="$base/img/$image">};
    push @head, qq{<meta name="twitter:card" content="summary_large_image">};
  }
  my $head = join("\n", @head);
  $html =~ s{<!--HEAD_LINKS-->}{$head};
  return $html;
}

# Builds one detail page from plain-text fields (escaped here) and returns the finished HTML.
#   slug, img (optional), pos (optional image focus), anchor + crumb (top-page section it belongs to),
#   kicker, name, lead, intro (optional), list_heading, items [[title, text]...],
#   facts [[label, text]...], tip, links [[label, url]...], others_heading, others [[slug, img, name]...]
sub render_detail {
  my ($l, $ui, $p) = @_;
  my %v = (slug => $p->{slug}, anchor => $p->{anchor});
  $v{$_} = esc($p->{$_}) for qw(crumb name lead tip list_heading others_heading);
  $v{area} = esc($p->{kicker});
  $v{"ui.$_"} = esc($ui->{$_}) for keys %$ui;

  if ($p->{img}) {
    my $pos = $p->{pos} ? qq{ style="object-position: $p->{pos}"} : '';
    $v{hero_class} = '';
    $v{hero_img}   = qq{    <img class="hero-art" src="../../img/$p->{img}" alt="" fetchpriority="high"$pos>};
  } else {
    $v{hero_class} = ' place-hero-plain';
    $v{hero_img}   = '';
  }

  $v{intro} = defined $p->{intro} ? esc($p->{intro}) : '';

  $v{highlights} = join("\n", map {
    "      <li><h3>" . esc($_->[0]) . "</h3><p>" . esc($_->[1]) . "</p></li>"
  } @{ $p->{items} });

  $v{facts} = @{ $p->{facts} } ? join("\n",
    qq{    <dl class="facts">},
    (map { "      <div><dt>" . esc($_->[0]) . "</dt><dd>" . esc($_->[1]) . "</dd></div>" } @{ $p->{facts} }),
    qq{    </dl>}) : '';

  $v{links_section} = @{ $p->{links} } ? join("\n",
    qq{  <section class="section place-section">},
    qq{    <div class="section-head">},
    qq{      <h2>$v{'ui.official'}</h2>},
    qq{      <p>$v{'ui.official_note'}</p>},
    qq{    </div>},
    qq{    <ul class="official">},
    (map { qq{      <li><a href="$_->[1]" target="_blank" rel="noopener">} . esc($_->[0]) . qq{<span aria-hidden="true"> ↗</span></a></li>} } @{ $p->{links} }),
    qq{    </ul>},
    qq{  </section>}) : '';

  $v{others} = join("\n", map {
    my ($slug, $img, $name) = @$_;
    qq{      <a class="other" href="../$slug/">}
      . ($img ? qq{<img src="../../img/$img" alt="" loading="lazy">} : '')
      . "<span>" . esc($name) . "</span></a>";
  } @{ $p->{others} });

  my $html = $place_tpl;
  $html =~ s{\{\{([\w.]+)\}\}}{ defined $v{$1} ? $v{$1} : die "Unknown placeholder {{$1}} in src/place.html" }ge;
  # A page with no intro paragraph gets no empty intro section
  $html =~ s{\s*<section class="section place-intro">\s*<p></p>\s*</section>}{} if $v{intro} eq '';

  my $page = "$p->{slug}/";
  spit("$dir/docs/$l->[1]/${page}index.html", localize($html, $l, $page, 2, $p->{img} || 'hero.jpg'));
  return $page;
}

# The link for this language from a list of { ja: [label, url], intl: [label, url] } (either may be absent)
sub links_for {
  my ($links, $code) = @_;
  return [ grep { defined } map { $code eq 'ja' ? $_->{ja} : $_->{intl} } @{ $links || [] } ];
}

my @pages;   # every page, for the sitemap

for my $l (@langs) {
  my ($code, $slug) = @$l;

  spit("$dir/docs/$slug/index.html", localize($tpl, $l, '', 1, 'hero.jpg'));
  push @pages, [$slug, ''];
  print "built docs/$slug/index.html\n";

  my $ui = $pdata->{ui}{$code} or die "No detail-page labels for $code";

  # Destinations
  for my $p (@places) {
    my $t = $p->{$code} or die "No detail text for $p->{slug} / $code";
    defined $t->{$_} or die "Missing $_ for $p->{slug} / $code" for qw(lead intro season access stay tip h);
    push @pages, [$slug, render_detail($l, $ui, {
      slug => $p->{slug}, img => $p->{img},
      anchor => 'destinations', crumb => label('dest.title', $code),
      kicker => label("$p->{key}.area", $code), name => label("$p->{key}.name", $code),
      lead => $t->{lead}, intro => $t->{intro},
      list_heading => $ui->{highlights}, items => $t->{h},
      facts => [[$ui->{season}, $t->{season}], [$ui->{access}, $t->{access}], [$ui->{stay}, $t->{stay}]],
      tip => $t->{tip}, links => links_for($p->{links}, $code),
      others_heading => $ui->{others},
      others => [ map { [$_->{slug}, $_->{img}, label("$_->{key}.name", $code)] } grep { $_->{slug} ne $p->{slug} } @places ],
    })];
  }

  # Seasons, routes, culture, travel basics
  my $text = json_file("pages/$code.json");
  my $ui2  = $text->{_ui} or die "No _ui labels in src/pages/$code.json";
  for my $p (@others) {
    my $g = $odata->{groups}{ $p->{group} } or die "Unknown group for $p->{slug}";
    my $t = $text->{ $p->{slug} } or die "No text for $p->{slug} in src/pages/$code.json";
    defined $t->{$_} or die "Missing $_ for $p->{slug} / $code" for qw(h tip);

    my @facts = map { [label($_->[0], $code), label($_->[1], $code)] } @{ $p->{facts} || [] };
    push @facts, [$ui2->{wear}, $t->{wear}]           if defined $t->{wear};
    push @facts, [$ui->{season}, $t->{when}]          if defined $t->{when};
    push @facts, [$ui2->{transport}, $t->{transport}] if defined $t->{transport};

    push @pages, [$slug, render_detail($l, $ui, {
      slug => $p->{slug}, img => $p->{img}, pos => $p->{pos},
      anchor => $g->{anchor}, crumb => label($g->{crumb}, $code),
      kicker => label($p->{kicker}, $code), name => label($p->{name}, $code),
      lead => label($p->{lead}, $code),
      intro => $p->{intro} ? label($p->{intro}, $code) : $t->{intro},
      list_heading => ($ui2->{ $g->{list} } // $ui->{ $g->{list} } // die "No label for $g->{list} / $code"),
      items => $t->{h}, facts => \@facts,
      tip => $t->{tip}, links => links_for($p->{links}, $code),
      others_heading => $ui2->{more},
      others => [ map { [$_->{slug}, $_->{img}, label($_->{name}, $code)] }
                  grep { $_->{group} eq $p->{group} && $_->{slug} ne $p->{slug} } @others ],
    })];
  }
  print "built docs/$slug/<page>/index.html x " . (@places + @others) . "\n";
}

if ($base ne '') {
  my $xml = qq{<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n};
  $xml .= "  <url><loc>" . page_url($_->[0], $_->[1], 1) . "</loc></url>\n" for @pages;
  $xml .= "</urlset>\n";
  spit("$dir/docs/sitemap.xml", $xml);
  spit("$dir/docs/robots.txt", "User-agent: *\nAllow: /\nSitemap: $base/sitemap.xml\n");
  print "built docs/sitemap.xml and docs/robots.txt for $base\n";
}
