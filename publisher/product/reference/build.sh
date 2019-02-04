#!/usr/bin/env bash
#
# Generate the reference "product" from the source ontologies
#
# Copyright (c) agnos.ai UK Ltd, 2019
# Author Jacobus Geluk
# Licensed under MIT License
#

#
# Looks silly but fools IntelliJ to see the functions in the included files
#
false && source ../../lib/_functions.sh

export SCRIPT_DIR="${SCRIPT_DIR}" # Yet another hack to silence IntelliJ
export speedy="${speedy:-0}"

if [[ -f ${SCRIPT_DIR}/product/reference/build-queries.sh ]] ; then
  # shellcheck source=build-cats.sh
  source ${SCRIPT_DIR}/product/reference/build-queries.sh
else
  source build-queries.sh # This line is only there to make the IntelliJ Bash plugin see build-queries.sh
fi

#
# You can limit the number of classes here to for instance 100 so that generating the reference
# doesn't take so long which is useful during development.
#
reference_max_classes=10000
#reference_max_classes=30

#
# Set reference_skip_content to true if you want to generate just the overall outline of the document or anything that goes fast.
# Will also only do "book-letter.pdf"
#
reference_skip_content=$(false ; echo $?)

#
# All document classes it needs to generate
#
reference_document_classes="book report"
#
# All page sizes in needs to generate
#
reference_page_sizes="a4 letter"
#
# All sides options it needs to generate for
#
reference_sides_options="twosided oneside"

if ((reference_skip_content)) ; then
  reference_document_classes="book"
  reference_page_sizes="a4"
  reference_sides_options="oneside"
fi

#
# Produce all artifacts for the reference product
#
function publishProductReference() {

  setProduct ontology || return $?
  export ontology_product_tag_root="${tag_root:?}"

  setProduct reference || return $?
  export reference_product_tag_root="${tag_root:?}"
  export reference_product_tag_root_url="${tag_root_url:?}"

  reference_script_dir="$(cd "${SCRIPT_DIR}/product/reference" && pwd)" ; export reference_script_dir
  reference_latex_dir="${reference_product_tag_root}"
  reference_data_dir="${reference_product_tag_root}/data"
  reference_query_dir="${reference_product_tag_root}/query"

  mkdir -p "${reference_data_dir}" "${reference_query_dir}" >/dev/null 2>&1

  export BIBINPUTS="${reference_script_dir}"

  #
  # Various stats that we maintain during generation of the reference, to be printed in the Statistics chapter
  #
  reference_stat_number_of_ontologies=0
  reference_stat_number_of_ontologies_without_label=0
  reference_stat_number_of_classes_without_superclass=0
  reference_stat_number_of_classes=0
  reference_stat_number_of_classes_without_label=0

  declare -A reference_array_ontologies
  declare -A reference_array_classes

  logBoolean reference_skip_content

  referenceGenerateTdb2Database || return $?
  referenceGeneratePrefixesAsSparqlValues || return $?
  referenceQueryListOfClasses || return $?

  #
  # Remove all generated files
  #
  for documentClass in ${reference_document_classes} ; do
    rm -vf "${documentClass}-"*
  done

  for documentClass in ${reference_document_classes} ; do
    for pageSize in ${reference_page_sizes} ; do
      for sides in ${reference_sides_options} ; do
        reference_base_name="${documentClass}-${pageSize}-${sides}"
        logRule "${reference_base_name} - Step: referenceGenerate"
        reference_file_noext="${reference_latex_dir}/${reference_base_name}"
        glos_file_noext="${reference_latex_dir}/${reference_base_name}-glossary"
        reference_tex_file="${reference_file_noext}.tex"
        glos_tex_file="${glos_file_noext}.tex"
        exec 3<> "${reference_tex_file}"
        exec 4<> "${glos_tex_file}"
        referenceGenerateLaTex "${documentClass}" "${pageSize}" "${sides}" || return $?
        exec 3>&-
        exec 4>&-
        #
        # Sort the glossary and filter out duplicates
        #
        sort --unique --key=1,2 --field-separator='}' --output="${glos_tex_file}" "${glos_tex_file}"
        referenceCompile "${documentClass}" "${pageSize}" "${sides}" || return $?
      done
    done
  done

  return 0
}

function referenceGeometry() {

  local -r documentClass="$1"
  local -r pageSize="$2"

  case ${documentClass} in
    referencexx)
      echo "${pageSize}paper, portrait, margin=1in"
      ;;
    *)
      echo "${pageSize}paper, portrait, margin=0.7in"
      ;;
  esac
}

function referenceGenerateLaTexDocumentClass() {

  local -r documentClass="$1"
  local -r pageSize="$2"
  local -r sides="$3"

  case "${sides}" in
    oneside)
      cat >&3 <<< "\documentclass[${pageSize}paper,${sides},openany]{${documentClass}}"
      ;;
    twosided)
      cat >&3 <<< "\documentclass[${pageSize}paper,${sides}]{${documentClass}}"
      ;;
    *)
      error "Unknown values for sides parameter: ${sides}"
      return 1
  esac

  return 0
}

function referenceGenerateLaTex() {

  local -r documentClass="$1"
  local -r pageSize="$2"
  local -r sides="$3"

  referenceGenerateLaTexDocumentClass $1 $2 $3 || return $?

  #
  # The preamble, see https://en.wikibooks.org/wiki/LaTeX/Document_Structure
  #
  cat >&3 << __HERE__
% \usepackage[T1]{fontenc} (use this with pdflatex but not with xelatex)
% \usepackage[utf8]{inputenc} (use this with pdflatex but not with xelatex)
\usepackage{fontspec} % use this with xelatex
\usepackage[english]{babel}
%\usepackage{csquotes}
\usepackage[backend=biber,style=numeric,sorting=ynt,maxbibnames=99]{biblatex}
\addbibresource{reference.bib}
\usepackage{enumitem}
\usepackage{graphicx}
\graphicspath{{/publisher/lib/images/}}
\usepackage{blindtext}
\usepackage{appendix}
\usepackage{booktabs}
\usepackage{longtable}
\usepackage{ragged2e}
\usepackage{array}
\usepackage{calc}
\usepackage{geometry}
\usepackage{imakeidx}
% \usepackage{showframe} % for debugging
\makeindex[intoc]
\geometry{$(referenceGeometry "${documentClass}" "${pageSize}")}
%
% One must be careful when importing hyperref. Usually, it has to be the last package to be imported, but there might
% be some exceptions to this rule.
%
% See https://www.overleaf.com/learn/latex/Hyperlinks#Linking_web_addresses
%
\PassOptionsToPackage{hyphens}{url}\usepackage{hyperref}
%\usepackage{hyperref}
\hypersetup{
    linktocpage=true,
    breaklinks=true,
    colorlinks=true,
    linkcolor=blue,
    anchorcolor=black,
    citecolor=green,
    filecolor=magenta,
    urlcolor=cyan,
    pdftitle={FIBO Reference},
    pdfauthor={EDM Council},
    bookmarksopen=true,
    pdfpagemode=FullScreen,
}
\urlstyle{same}
%
% Headers and footers
%
\usepackage{etoolbox}
\usepackage{lastpage}
\usepackage{fancyhdr}
\patchcmd{\part}{\thispagestyle{plain}}{\thispagestyle{fancy1}}{}{}
\patchcmd{\chapter}{\thispagestyle{plain}}{\thispagestyle{fancy1}}{}{}
__HERE__

  case "${sides}" in
    twosided)
      cat >&3 << __HERE__
%
% Redefine the fancy page style
%
\fancypagestyle{fancy1}{
  \fancyhf{} % Clear header and footer
  \fancyhead[LE,RO]{EDM Council}
  \fancyhead[RE,LO]{FIBO Reference}
  \fancyfoot[CE,CO]{\leftmark}
  \fancyfoot[LE,RO]{\thepage\ of \pageref{LastPage}}
  \renewcommand{\headrulewidth}{0.4pt} % Line at the header visible
  \renewcommand{\footrulewidth}{0.4pt} % Line at the footer visible
}
%
% Redefine the plain page style
%
\fancypagestyle{plain}{
  \fancyhf{} % Clear header and footer
  \fancyhead[LE,RO]{EDM Council}
  \fancyhead[RE,LO]{FIBO Reference}
  \fancyfoot[CE,CO]{\leftmark}
  \fancyfoot[LE,RO]{\thepage\ of \pageref{LastPage}}
  \renewcommand{\headrulewidth}{0.4pt} % Line at the header visible
  \renewcommand{\footrulewidth}{0.4pt} % Line at the footer visible
}

__HERE__
      ;;
    oneside)
      cat >&3 << __HERE__
%
% Redefine the fancy page style
%
\fancypagestyle{fancy1}{
  \fancyhf{} % Clear header and footer
  \rhead{EDM Council}
  \lhead{FIBO Reference}
  \lfoot{\leftmark}
  \rfoot{\thepage\ of \pageref{LastPage}}
  \renewcommand{\headrulewidth}{0.4pt} % Line at the header visible
  \renewcommand{\footrulewidth}{0.4pt} % Line at the footer visible
}
%
% Redefine the plain page style
%
\fancypagestyle{plain}{
  \fancyhf{} % Clear header and footer
  \lfoot{\leftmark}
  \rfoot{\thepage\ of \pageref{LastPage}}
  \renewcommand{\headrulewidth}{0pt}   % Line at the header invisible
  \renewcommand{\footrulewidth}{0.4pt} % Line at the footer visible
}
__HERE__
      ;;
    *)
      error "Unknown number of page sides: ${sides}"
      return 1
      ;;
  esac

  cat >&3 << __HERE__
%
% glossaries package has to come after hyperref
% See http://mirrors.nxthost.com/ctan/macros/latex/contrib/glossaries/glossariesbegin.html
%
\usepackage[acronym,toc]{glossaries}
\loadglsentries{${reference_base_name}-glossary}
\makeglossaries
__HERE__

  referenceCreateGlossaryFile || return $?

  cat >&3 << __HERE__
\begin{document}
%\setmainfont{Nimbus Sans L}
\setmainfont{TeX Palladio L}
%\setmainfont{TeXGyreHerosCondensed}
%\setmainfont{TeX Gyre Adventor}
%\maketitle
__HERE__

  referenceGenerateTitle || return $?

  cat >&3 <<< "\part{Intro}"

  referenceGenerateAbstract "${documentClass}" || return $?

  cat >&3 <<< "\setcounter{tocdepth}{2}"
  cat >&3 <<< "\tableofcontents{}"

  referenceGenerateSectionIntro || return $?

  cat >&3 <<< "\part{Reference}"

  referenceGenerateSectionOntologies  "${documentClass}" "${pageSize}" || return $?
  referenceGenerateSectionClasses     "${documentClass}" "${pageSize}" || return $?
  referenceGenerateSectionProperties  "${documentClass}" "${pageSize}" || return $?
  referenceGenerateSectionIndividuals "${documentClass}" "${pageSize}" || return $?
  referenceGenerateSectionConclusion || return $?

  cat >&3 <<< "\part{Appendices}"
  cat >&3 <<< "\appendix"
  cat >&3 <<< "\addappheadtotoc"

  referenceGenerateSectionPrefixes || return $?
  referenceGenerateSectionStatistics || return $?
  referenceGenerateSectionVersion || return $?

  cat >&3 << __HERE__
\setglossarystyle{altlist}
\glsaddall
\printglossary[type=\acronymtype]
\glsaddall
\printglossary[title=Glossary, toctitle=Glossary]
\printbibliography[heading=bibintoc]
\printindex
\end{document}
__HERE__

  return 0
}

function referenceCreateGlossaryFile() {

  cat >&4 << __HERE__
\newacronym{rdf}{RDF}{Resource Definition Framework}
\newacronym{owl}{OWL}{Web Ontology Language}
\newacronym{fibo}{FIBO}{Financial Industry Business Ontology}
\newacronym{omg}{OMG}{Object Management Group}
\newacronym{edmc}{EDM Council}{Enterprise Data Management Council}
__HERE__

  return 0
}

function referenceAddGlossaryTerm() {

  local -r label="$(escapeLaTexLabel "$1")"
  local -r name="$(escapeLaTex "$1")"
  # shellcheck disable=SC2155
  local description="$(escapeLaTex "$2")"
  #
  # Remove the last dot from the line if its there because LaTex will add it again
  #
  [ "${description: -1}" == "." ] && description="${description::-1}"

  cat >&4 << __HERE__
\newglossaryentry{${label}}{name={${name}},description={${description}}}
__HERE__

}

function referenceGenerateTitle() {

  cat >&3 << __HERE__
\begin{titlepage}

\newcommand{\HRule}{\rule{\linewidth}{0.5mm}}

\center

%\textsc{\LARGE Enterprise Data Management Council}\\\\[1.5cm]
%\textsc{\Large FIBO}\\\\[0.5cm]
%\textsc{\large Financial Industry Business Ontology}\\\\[0.5cm]

\LARGE Enterprise Data Management Council\\\\[1.5cm]
\Large FIBO\\\\[0.5cm]
\large Financial Industry Business Ontology\\\\[0.5cm]

\HRule \\\\[0.4cm]
{ \huge \bfseries Reference}\\\\[0.4cm]
\HRule \\\\[1.5cm]

{\large \today}\\\\[2cm]

\includegraphics{edmcouncil-logo-large}\\\\[1cm]

\vfill

\end{titlepage}
__HERE__

  return 0
}

function referenceGenerateAbstract() {

  local -r documentClass="$1"

  [ "${documentClass}" == "book" ] && return 0

  cat >&3 << __HERE__
\begin{abstract}
\blindtext
\end{abstract}
__HERE__

  return 0
}

function referenceGenerateSectionIntro() {

  #
  # TODO: Make this generic so that it can support any ontology family, not just FIBO
  #

  cat >&3 << __HERE__
\chapter*{What is FIBO?}
\index{What is FIBO?}

  The \textit{\acrfull{fibo}}\cite{fiboprimer} is the industry standard\index{industry standard} resource for
  the definitions of business concepts in the financial services industry.
  It is developed and hosted by the \textit{\acrfull{edmc}} and is published in a
  number for formats for operating use and for business definitions.
  It is also standardized through the \textit{\acrfull{omg}}\cite{omgwebsite,omgedmcwebsite}.
  \acrshort{fibo} is developed as a series of ontologies in the \textit{\acrfull{owl}}.
  As such it is not a data model but a representation of the “things in the world” of financial services.
  The use of logic ensures that each real-world concept is framed in a way that is unambiguous and that is readable
  both by humans and machines.
  These common concepts have been reviewed by \acrshort{edmc} member firms over a period of years and represent a
  consensus of the common concepts as understood in the industry and as reflected in industry data models and message
  standards.

\chapter*{About this document}

  This document is generated by the so called "ontology publisher"\cite{ontologypublisher} which used the
  FIBO ontologies that are hosted on Github{fibogithub} (in a members-only repository).
  See chapter "\nameref{chap:version}" (at page \pageref{chap:version}) to see from which particular "git branch" this
  document has been generated.

__HERE__

  return 0
}

function referenceGenerateSectionConclusion() {

  cat >&3 << __HERE__
\chapter*{Conclusion}
\blindtext
__HERE__

  return 0
}

function referenceGenerateSectionOntologies() {

  local -r documentClass="$1"
  local -r pageSize="$2"

  local ontologyIRI
  local ontologyVersionIRI
  local ontologyLabel
  local abstract
  local preferredPrefix
  local maturityLevel

  logRule "${reference_base_name} - Step: referenceGenerateSectionOntologies"

  referenceQueryListOfOntologies || return $?

  logVar reference_results_file

  cat >&3 << __HERE__
\chapter{Ontologies}
\index{Ontologies}

  This chapter enumerates all the (OWL) ontologies that play a role in ${ONTPUB_FAMILY}.

__HERE__

  ((reference_skip_content)) && return 0

  #
  # Process each line of the TSV file with "read -a" which properly deals
  # with spaces in class labels and definitions etc.
  #
  # ?ontologyIRIstr	?ontologyVersionIRIstr ?ontologyPrefix ?ontologyLabelStr
  # ?abstractStr ?preferredPrefixStr ?maturityLevelStr
  #
  while IFS=$'\t' read ontologyIRI ontologyVersionIRI prefix ontologyLabel abstract preferredPrefix maturityLevel ; do

    [[ "${ontologyIRI}" == "" ]] && continue
    [[ "${ontologyIRI:0:1}" == "?" ]] && continue

    ontologyIsInTestDomain "${ontologyIRI}" || continue

    ontologyIRI="$(stripQuotes "${ontologyIRI}")"
    ontologyVersionIRI="$(stripQuotes "${ontologyVersionIRI}")"
    prefix="$(stripQuotes "${prefix}")"
    ontologyLabel="$(stripQuotes "${ontologyLabel}")"
    abstract="$(stripQuotes "${abstract}")"
    preferredPrefix="$(stripQuotes "${preferredPrefix}")"
    maturityLevel="$(stripQuotes "${maturityLevel}")"

    logRule "Ontology:"
    logVar ontologyIRI
    logVar ontologyVersionIRI
    logVar prefix
    logVar ontologyLabel
    logVar abstract
    logVar preferredPrefix
    logVar maturityLevel

    if [[ "${prefix}" == "" ]] ; then
      prefix="${preferredPrefix}"
      preferredPrefix=""
    fi

    if [[ "${ontologyLabel}" == "${prefix}" ]] ; then
      ontologyLaTexLabel=""
      ontologyLabel=""
    else
      ontologyLaTexLabel="$(escapeLaTexLabel "${ontologyLabel}")"
      ontologyLabel="$(escapeLaTex "${ontologyLabel}")"
    fi

    if [[ -n "${prefix}" ]] ; then
      cat >&3 << __HERE__
{\renewcommand\addcontentsline[3]{} \section{${prefix}}}
\label{sec:${prefix}} \index{${prefix}}
__HERE__
    elif [[ -n "${ontologyLabel}" ]] ; then
      cat >&3 << __HERE__
{\renewcommand\addcontentsline[3]{} \section{${ontologyLabel}}}
\label{sec:${ontologyLaTexLabel}} \index{${ontologyLabel}}
__HERE__
    else
      continue
    fi

    #
    # Label
    #
    if [[ -n "${ontologyLabel}" ]] ; then
      cat >&3 <<< "\textbf{$(escapeAndDetokenizeLaTex "${ontologyLabel}")} \\\\"
      if [[ -n "${prefix}" && -n "${abstract}" ]] ; then
        referenceAddGlossaryTerm "${prefix}" "${abstract}"
      fi
    else
      reference_stat_number_of_ontologies_without_label=$((reference_stat_number_of_ontologies_without_label + 1))
    fi
    #
    # abstract
    #
    if [[ -n "${abstract}" ]] ; then
      cat >&3 <<< "$(escapeAndDetokenizeLaTex "${abstract}")"
    else
      cat >&3 <<< "No abstract available."
    fi

    cat >&3 <<< "\\\\"
    cat >&3 <<< "\begin{description}[topsep=1.0pt]"
    #
    # Preferred prefix
    #
    if [[ -n "${preferredPrefix}" ]] ; then
      cat >&3 <<< "\item [Prefix] $(escapeAndDetokenizeLaTex "${preferredPrefix}")"
    fi
    #
    # Maturity level
    #
    if [[ -n "${maturityLevel}" ]] ; then
      cat >&3 <<< "\item [Maturity] $(escapeAndDetokenizeLaTex "${maturityLevel}")"
    fi
    #
    # Ontology Version IRI
    #
    if [[ -n "${ontologyVersionIRI}" ]] ; then
      cat >&3 <<< "\item [Version IRI] \url{$(escapeAndDetokenizeLaTex "${ontologyVersionIRI}")}"
    fi

    cat >&3 <<< "\end{description}"

    reference_stat_number_of_ontologies=$((reference_stat_number_of_ontologies + 1))

  done < "${reference_results_file}"

  return 0
}

function referenceGenerateSectionClasses() {

  local -r documentClass="$1"
  local -r pageSize="$2"

  logRule "${reference_base_name} - Step: referenceGenerateSectionClasses"

  local reference_results_file # will get the name of the results value after the call to bookQueryListOfClasses()
  local reference_results_file_number_of_lines # also set by bookQueryListOfClasses()

  referenceQueryListOfClasses || return $?

  cat >&3 << __HERE__
\chapter{Classes}
\index{Classes}

  This chapter enumerates all the (OWL) classes\index{OWL classes} that play a role in ${ONTPUB_FAMILY}.
  Per Class we show the following information:

  \begin{description}
    \item [Title] The so-called "local name" of the OWL class, prefixed with the standard prefix for its namespace. See Namespace below.
    \item [Label] The english label of the given OWL Class.
    \item [Namespace] The namespace in which the OWL Class resides, leaving out the local name.
    \item [Definition] The definition of the OWL Class.
    \item [Explanatory Note] An optional explanatory note.
  \end{description}
__HERE__

  ((reference_skip_content)) && return 0

  local classIRI
  local prefName
  local namespace
  local classLabel
  local definition
  local explanatoryNote
  local numberOfClasses=0

  #
  # Process each line of the TSV file with "read -a" which properly deals
  # with spaces in class labels and definitions etc.
  #
  while IFS=$'\t' read classIRI classPrefName namespace classLabel definition explanatoryNote ; do

    [[ "${classIRI}" == "" ]] && continue
    [[ "${classPrefName}" == "" ]] && continue
    [[ "${classIRI:0:1}" == "?" ]] && continue

    if ((numberOfClasses > reference_max_classes)) ; then
      warning "Stopping at ${reference_max_classes} since we're running in dev mode"
      break
    fi
    numberOfClasses=$((numberOfClasses + 1))

    classIRI="$(stripQuotes "${classIRI}")"
    classPrefName="$(stripQuotes "${classPrefName}")"
    namespace="$(stripQuotes "${namespace}")"
    classLabel="$(stripQuotes "${classLabel}")"
    definition="$(stripQuotes "${definition}")"
    explanatoryNote="$(stripQuotes "${explanatoryNote}")"

    classLaTexLabel="$(escapeLaTexLabel "${classPrefName}")"
    classPrefName="$(escapeLaTex "${classPrefName}")"

#    logVar classIRI
#    logVar classPrefName
#    logVar namespace
#    logVar classLabel
#    logVar definition
#    logVar explanatoryNote

    cat >&3 << __HERE__
{\renewcommand\addcontentsline[3]{} \section{${classPrefName}}}
\label{sec:${classLaTexLabel}} \index{${classPrefName#*:}}
__HERE__

    #
    # Label
    #
    if [[ -n "${classLabel}" ]] ; then
      cat >&3 <<< "\textbf{$(escapeAndDetokenizeLaTex "${classLabel}")} \\\\"
      if [ -n "${classLabel}" ] && [ -n "${definition}" ] ; then
        referenceAddGlossaryTerm "${classLabel}" "${definition}"
      fi
    else
      reference_stat_number_of_classes_without_label=$((reference_stat_number_of_classes_without_label + 1))
    fi

    #
    # Definition
    #
    if [[ -n "${definition}" ]] ; then
      cat >&3 <<< "$(escapeAndDetokenizeLaTex "${definition}")"
    else
      cat >&3 <<< "No definition available."
    fi

    cat >&3 <<< "\\\\"
    cat >&3 <<< "\begin{description}[topsep=1.0pt]"
    #
    # Namespace
    #
    cat >&3 <<< "\item [Namespace] \hfill \\\\ {\fontsize{8}{1.2}\selectfont $(escapeAndDetokenizeLaTex "${namespace}")}"
    #
    # Super classes
    #
    referenceGenerateListOfSuperclasses "${classIRI}" || return $?
    #
    # Subclasses
    #
    referenceGenerateListOfSubclasses "${classIRI}" || return $?
    #
    # Explanatory Note
    #
    [[ -n "${explanatoryNote}" ]] && cat >&3 <<< "\item [Explanatory note] \hfill \\\\ $(escapeAndDetokenizeLaTex "${explanatoryNote}")"

    cat >&3 <<< "\end{description}"

    reference_stat_number_of_classes=$((reference_stat_number_of_classes + 1))
    if ((reference_stat_number_of_classes % 100 == 0)) ; then
      logItem "Progress Classes Chapter" "$((100 * reference_stat_number_of_classes / reference_results_file_number_of_lines))% (${reference_stat_number_of_classes}/${reference_results_file_number_of_lines})"
      break
    fi
  done < "${reference_results_file}"

  if ((reference_stat_number_of_classes == 0)) ; then
    error "Didn't process any classes, something went wrong"
    return 1
  fi

    cat >&3 << __HERE__
__HERE__

  return 0
}

function referenceGenerateSectionProperties() {

  local -r documentClass="$1"
  local -r pageSize="$2"

  logRule "${reference_base_name} - Step: referenceGenerateSectionProperties"

  cat >&3 << __HERE__
\chapter{Properties}

  This chapter enumerates all the (OWL) properties that play a role in ${ONTPUB_FAMILY}.

  TODO

  \blindtext
__HERE__

  return 0
}

function referenceGenerateSectionIndividuals() {

  local -r documentClass="$1"
  local -r pageSize="$2"

  logRule "${reference_base_name} - Step: referenceGenerateSectionIndividuals"

  cat >&3 << __HERE__
\chapter{Individuals}

  This chapter enumerates all the (OWL) properties that play a role in ${ONTPUB_FAMILY}.

  TODO

  \blindtext
__HERE__

  return 0
}

function referenceGenerateSectionPrefixes() {

  [[ -f "${TMPDIR}/reference-prefixes.txt" ]] || return 0

  local -r numberOfPrefixes=$(cat "${TMPDIR}/reference-prefixes.txt" | wc -l)

  logVar numberOfPrefixes

  ((numberOfPrefixes == 0)) && return 0

  cat >&3 << __HERE__
\chapter{Prefixes}
\index{Prefixes}
\begin{scriptsize}
\begin{description}[leftmargin=6.2cm,labelwidth=3cm]
__HERE__

#\begin{description}[leftmargin=6.2cm,labelwidth=\widthof{fibo-fbc-fct-eufseind}]

  while read prefix namespace ; do
    cat >&3 <<< "\item [${prefix}] \url{${namespace}}"
  done < <( ${SED} -n 's/("\(.*\):"\s<\(.*\)>)/\1 \2/g;p' "${TMPDIR}/reference-prefixes.txt" )

  cat >&3 <<< "\end{description}"
  cat >&3 <<< "\end{scriptsize}"

  return 0
}

function referenceGenerateSectionStatistics() {

    cat >&3 << __HERE__
\chapter{Statistics}

  TODO: To be extended with some more interesting numbers.

  \begin{description}
    \item [Number of ontologies] ${reference_stat_number_of_ontologies}
      \begin{description}
        \item [Without a label] ${reference_stat_number_of_ontologies_without_label}
      \end{description}
    \item [Number of classes] ${reference_stat_number_of_classes}
      \begin{description}
        \item [Without a label] ${reference_stat_number_of_classes_without_label}
        \item [Without a superclass] ${reference_stat_number_of_classes_without_superclass}
      \end{description}
  \end{description}
__HERE__

  return 0
}

function referenceGenerateSectionVersion() {

  local -r maxLogLines=100

    cat >&3 << __HERE__
\chapter*{Version}
\label{chap:version}

  TODO: To be extended

  \begin{description}
    \item [Git Branch] ${GIT_BRANCH} which was the branch from which this reference has been generated.
    \item [Git Tag] ${GIT_TAG_NAME}
  \end{description}
__HERE__

    cat >&3 << __HERE__
\section*{Log}

%
% column type defining the Commit column C
%
\newcolumntype{C}{>{\small\ttfamily}p{1.2cm}}
%
% column type defining the Author column A
%
%\newcolumntype{A}{>{\small\RaggedRight}p{2.3cm}}
\newcolumntype{A}{>{\small\raggedright\let\newline\\\\\arraybackslash\hspace{0pt}}p{2.4cm}}
%
% column type defining the Date column D
%
%\newcolumntype{D}{>{\small}p{1.9cm}}
\newcolumntype{D}{>{\small\raggedright\let\newline\\\\\arraybackslash\hspace{0pt}}p{1.9cm}}
%
% column type defining the Description column P
%
\newcolumntype{P}{>{\raggedright\let\newline\\\\\arraybackslash\hspace{0pt}}p{10cm}}

\setlength{\tabcolsep}{5pt}
\setlength\LTleft{0pt}
\setlength\LTright{0pt}
\begin{longtable}[c]{@{\extracolsep{\fill}}CADP@{}}
\caption{Git Commit Log.\label{gitcommitlog}}\\\\
\hline
\normalfont\textbf{Commit} &
\textbf{Author} &
\textbf{Date} &
\textbf{Comment} \\\\ \hline
\endfirsthead

\hline
\multicolumn{4}{c}{Continuation of the Git Commit Log \ref{gitcommitlog}}\\\\
\hline
\normalfont\textbf{Commit} &
\textbf{Author} &
\textbf{Date} &
\textbf{Comment} \\\\ \hline
\endhead

\hline
\endfoot

\hline
\multicolumn{4}{c}{End of max ${maxLogLines} lines of the git log}
\endlastfoot
__HERE__

  while IFS=$(printf "\t") read -r commit author date comment ; do
   cat >&3 <<< "\href{https://github.com/edmcouncil/fibo/commit/${commit}}{${commit}} & ${author} & ${date} & $(escapeLaTex "${comment}") \\\\"
#  cat >&3 <<< "\href{https://github.com/edmcouncil/fibo/commit/${commit}}{${commit}} & author & date & test \\\\"
  done < <(referenceGenerateSectionVersionGitLog)

  cat >&3 << __HERE__
\end{longtable}
__HERE__

  return 0
}

function referenceGenerateSectionVersionGitLog() {

  cd "${source_family_root}"
  git log --date=short --pretty=format:"%h%x09%an%x09%ad%x09%s" | \
    head -n ${maxLogLines} | \
    ${SED} -e 's/DennisWisnosky/Dennis Wisnosky/g'
}

function referenceGenerateListOfSuperclasses() {

  local -r classIRI="$1"
  local line

  local reference_results_file # will get the name of the results value after the call to bookQueryListOfClasses

  referenceQueryListOfSuperClasses || return $?

  if [[ ! -f "${reference_results_file}" ]] ; then
    error "Could not find ${reference_results_file}"
    return 1
  fi

  local -a superClassArray

  mapfile -t superClassArray < <(${SED} -n -e "s@^\"${classIRI}\"\(.*\)@\1@p" "${reference_results_file}")

  local -r numberOfSuperClasses=${#superClassArray[*]}

  if ((numberOfSuperClasses == 0)) ; then
#   warning "${classIRI} does not have any super classes"
    reference_stat_number_of_classes_without_superclass=$((reference_stat_number_of_classes_without_superclass + 1))
    return 0
  fi

  if ((numberOfSuperClasses > 1)) ; then
    cat >&3 << __HERE__
\item [Superclasses] \hfill
\begin{itemize}[noitemsep,nolistsep,topsep=1.0pt]
__HERE__
  fi

  #
  # Process each line of the TSV file with "read -a" which properly deals
  # with spaces in class labels and definitions etc.
  #
  for line in "${superClassArray[@]}" ; do

    set -- ${line}

    [[ "$1" == "" ]] && continue
    [[ "$2" == "" ]] && continue

#   superClassIRI="$(stripQuotes "$1")"
    superClassPrefName="$(stripQuotes "$2")"

    if ((numberOfSuperClasses > 1)) ; then
      cat >&3 <<< "\item $(referenceClassReference "${superClassPrefName}")"
    else
      cat >&3 <<< "\item [Superclass] $(referenceClassReference "${superClassPrefName}")"
    fi

  done

  if ((numberOfSuperClasses > 1)) ; then
    cat >&3 <<< "\end{itemize}"
  fi

}

function referenceClassReference() {

  local classPrefName="$1"
  local -r classLaTexLabel="$(escapeLaTexLabel "${classPrefName}")"

  classPrefName="$(escapeLaTex "${classPrefName}")"

  echo -n "${classPrefName}"
  echo -n "\index{${classPrefName#*:}}"
# echo -n " (Section~\ref{sec:${classLaTexLabel}} at page~\pageref{sec:${classLaTexLabel}})"
  echo -n " (page~\pageref{sec:${classLaTexLabel}})"
}

function referenceGenerateListOfSubclasses() {

  local -r classIRI="$1"

  local reference_results_file # will get the name of the results value after the call to bookQueryListOfClasses

  #
  # We use the super classes list to find the subclasses of a given class
  #
  referenceQueryListOfSuperClasses || return $?

  if [[ ! -f "${reference_results_file}" ]] ; then
    error "Could not find ${reference_results_file}"
    return 1
  fi

  local -a subclassArray

  mapfile -t subclassArray < <(${SED} -n -e "s@^\"\(.*\)\"\t\"${classIRI}\".*@\1@p" "${reference_results_file}")

  local -r numberOfSubclasses=${#subclassArray[*]}

  if ((numberOfSubclasses == 0)) ; then
    return 0
  fi

  if ((numberOfSubclasses > 1)) ; then
    cat >&3 << __HERE__
\item [Subclasses] \hfill
\begin{itemize}[noitemsep,nolistsep,topsep=1.0pt]
__HERE__
  fi

  #
  # Process each line of the TSV file with "read -a" which properly deals
  # with spaces in class labels and definitions etc.
  #
  for line in "${subclassArray[@]}" ; do

    set -- ${line}

    [[ "$1" == "" ]] && continue

    subclassIRI="$(stripQuotes "$1")"
    subclassPrefLabel="${reference_array_classes[${subclassIRI},prefName]}"

    [[ "${subclassPrefLabel}" == "" ]] && continue

    if ((numberOfSubclasses > 1)) ; then
      cat >&3 <<< "\item $(referenceClassReference "${subclassPrefLabel}")"
    else
      cat >&3 <<< "\item [Subclass] $(referenceClassReference "${subclassPrefLabel}")"
    fi

  done

  if ((numberOfSubclasses > 1)) ; then
    cat >&3 <<< "\end{itemize}"
  fi

}

function referenceFilterCompilerOutput() {

  grep -v "LaTeX Warning: Citation" | \
  grep -v "LaTeX Warning: Reference \`LastPage\'" | \
  grep -v "^(/usr/local/texlive"
}

function referenceCallXeLaTex() {

  logRule "${reference_base_name} - xelatex run $1"
  xelatex -halt-on-error "${reference_base_name}" | referenceFilterCompilerOutput
  return ${PIPESTATUS[0]}
}

function referenceCallMakeGlossaries() {

  logRule "${reference_base_name} - makeglossaries"
  makeglossaries "${reference_base_name}"
}

function referenceCallBiber() {

  logRule "${reference_base_name} - biber"
  biber "${reference_base_name}"
}

function referenceCallMakeIndex() {

  logRule "${reference_base_name} - makeindex"
  makeindex "${reference_base_name}"
}

function referenceCompile() {

  local -r documentClass="$1"
  local -r pageSize="$2"
  local -r sides="$3"

  log "referenceCompile documentClass=${documentClass} pageSize=${pageSize} sides=${sides}"

  (
    cd "${reference_latex_dir}" || return $?
#      -interaction=batchmode \
    export max_print_line=100
    referenceCallXeLaTex 1 || return $?
    referenceCallMakeGlossaries || return $?
    referenceCallXeLaTex 2 || return $?
    referenceCallBiber || return $?
    referenceCallXeLaTex 3 || return $?
    referenceCallMakeIndex || return $?
    referenceCallXeLaTex 4 || return $?
  )
  return $?
}