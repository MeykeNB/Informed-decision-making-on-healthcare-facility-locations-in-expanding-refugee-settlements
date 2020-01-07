;;;;;;; SETTING UP ;;;;;;;
; Load extension to enable loading gis data
extensions [
  gis
  csv
]
; Defining global datasets
globals [
  elevation-dataset
  roads-dataset
  coordinates-dataset
  kansje
  path
  pop_max
;  camps ;;  List holding the camp numbers
;  endnrs ;; List holding the total number of refugees that is counted in the camps in February 2019 (last count).
  countshelters ;; List holding the number of refugees in the camps counted at the current tick
  counter
  distHF-pref distRoad-pref distneighb-pref
  shelters_to_create
  facilities_to_create
  last-count
  ticks-last-count
  consultations
  initial-capacity
  future-modus
  radius
  space-variable
  prediction-accuracy
  future-regression

  ; for SA:
  chance-get-sick
  chance-remain-sick
  pop_max_SA


  ; reporters:
  average-distance
  covered-shelters
  predicted-shelters
  sumshelters
  sumwaiting-patients
  sumovercapacity
  unusedcapacity
]

;; Defining breeds of agentsets
breed [ shelters shelter ]
breed [ facilities facility ]
breed [ drawers drawer ]
breed [ tracers tracer ]

;; Defining what is tracked for each patch
patches-own [ elevation lat long available  distRoad distHF numneighb ] ; OPTION add [ covered?] ??
shelters-own [ hh-size campnr covered? available-here sick? dist-HF prediction]
facilities-own [ capacity overcapacity; these two are about the number of patients that may be connected to 1 healthpost. (SPHERE standard = 1:10.000, so here it is 10.000/100/hh-size (4.57) = 21,861 = 22
  in-consult waiting-patients] ; these two are about the number of patients that are currently using this facility.
links-own [travel]


;;;;;;; SETTING UP THE BACKGROUND ;;;;;;; (elevation, roads, initial camps, initial facilities) ;;;

to setup-world
  clear-all
 ; new-seed
  import-world "RoadsLikeDashboard" ; "RoadsLikeASCShapefile"
  import-pcolors "RoadsLikeDashboard.png" ;  "RoadsLikeASCShapefile.png"

  set pop_max (856 / 4.57435252023618) ; corresponds to September 2017
  set initial-capacity 22 ; (SPHERE standard = 1:10.000, so here it is 10.000/100/hh-size (4.57) = 21,861 = 22)
  set facilities_to_create 2
  set chance-get-sick 0.346344161
  set chance-remain-sick 0.021043838
end


to setup
;  clear-all
; ; new-seed
;  import-world "RoadsLikeDashboard" ; "RoadsLikeASCShapefile"
;  import-pcolors "RoadsLikeDashboard.png" ;  "RoadsLikeASCShapefile.png"
  reset-ticks

  set future-modus False
   ; define the distance requirement between shelters:
  ifelse space-variable = 3 [
    set space-usage "SPHERE standard (45m2/person)"
    set radius 30 ]
  [ifelse space-variable = 2 [
    set space-usage "improvement target (35m2/person"
    set radius 23 ]
  [if space-variable = 1 [
    set space-usage "current situation (22m2/person)"
      set radius 14] ] ]


;
;  ifelse space-usage = "SPHERE standard (45m2/person)" [set radius 30]
;  [ifelse space-usage = "improvement target (35m2/person" [set radius 23]
;    [if space-usage = "current situation (22m2/person)" [set radius 14] ] ]


  patches-availability
  set kansje patch-set patches with [pcolor <= 120 and pcolor != black and elevation >= 8.5] ; the first part removes all roads (pink color)
  ask kansje [ set distRoad ( min [distance myself] of patches with [pcolor = 125] )
    if distRoad = 0 [set distRoad ( 0.01) ] ]

  test-setup-camp
  set last-count (count shelters with [prediction = False])
  set ticks-last-count ticks
  ;create-random-facilities

;  set endnrs ( list 31917 49453 21786 )
;  set camps ( list 14 15 16 ) ; creates a list [14 15 16]
end

to patches-availability ;; LET OP: telt aantal shelters, niet aantal refugees
  ask patches [
    set available radius

    ;; Elevation difference with neighboring patches lowers the amount of available places on a patch.
    let elev-dif ([elevation] of (max-one-of neighbors [elevation] ) - [elevation] of self )

    ifelse elev-dif = 0 [set available available] [
    ifelse elev-dif > 0.6 [set available (available * 0.5)]
    [ifelse elev-dif > 0.4 [set available (available * 0.65)]
      [ if elev-dif > 0.2 [set available (available * 0.8)]
    ]]   ]

    let numshelters count shelters-here ; counts the number of shelters on this patch
    set available (available - numshelters)

    ;; maken dat shelters verhuizen na initial-setup als er teveel op 1 plek staan.
  ]
end

to create-new-shelters;

  ifelse future-modus = True [  ; if the future-modus is on, shelters are created, which will be removed afterwards, so the original countshelters and shelters_to_create can be overwritten.
    ask shelters with [prediction = True] [die]
    set countshelters (count shelters)
    ifelse future-regression = 1 [
      if countshelters > 0 [
        if ticks != ticks-last-count [
;          print("Future-regression = 1, countshelters > 0, ticks != ticks-last-count")
      let past-growth ((countshelters - last-count) / (ticks - ticks-last-count))
          set shelters_to_create past-growth
          print("Shelters to create is")
            print(shelters_to_create)
    ] ] ]
    [ set shelters_to_create 20]

;    if prediction-accuracy != 100 [
      ;;;If future-modus is true, but prediction-accuracy = 0, we create shelters as follows:.

    ; MAKE SHELTERS
    while [(count shelters) < (countshelters + shelters_to_create)] [ ; shelters are created one-by-one, to mimic reality better.
    set kansje kansje with [available >= 1]
    set kansje kansje with [count shelters-here = 0]
    let options kansje with [shelters in-radius (radius * 1.5) != nobody] ;Decide: include this in the create-shelters loop or keep it here.
    ask options [set numneighb (count shelters in-radius (radius)) ]

    create-shelters 1 [
      set shape "campsite"
      set size 4
      set covered? False
      set sick? False
      set prediction True
      set-preferences

      let best-location min-one-of options [location-utility]
      move-to best-location

      let current-available ([available] of patch-here)
      ask patches in-radius (0.5 * radius) [set available (available - 1) ]
      ask patches in-radius 3 [set available 0]
      if current-available > 1 [ask patch-here [set available 0.5]] ; This makes this still an option for facilities
      set available-here ([available] of patch-here)
        ]
        set predicted-shelters (count shelters with [prediction = True])
      ]
  ] ;; If prediction-accuracy != 100, de predicted shelters worden weggehaald in Python.

 [ ;;; if future-modus is false:

    if prediction-accuracy = 100 [
  ; If prediction-accuracy = 100, you want predicted shelters to become real.

    let num_predictionshelters (count shelters with [prediction = True])
      print("the number of predicted shelters is")
      print(num_predictionshelters)


    ifelse num_predictionshelters >= shelters_to_create [ ; if future-modus = False, shelters_to_create is determined in the 'go'-command.
    ; If there are sufficient predicted shelters to become real:
        ifelse shelters_to_create > 0 [
          ask n-of shelters_to_create (shelters with [prediction = True]) [set prediction False set size 4]
         set predicted-shelters (count shelters with [prediction = True])
        ]

        ;;; toegevoegd 27/10 na 'Too Many Shelters' verification mistake:
        ;;; if shelters to create < 0:
        [ set predicted-shelters (count shelters with [prediction = True])
          ask shelters with [prediction = True] [die]]]
      ;;;;;;

   [ ; If there are not sufficient predicted shelters, you also want to create new shelters:
      let num_create_not_prediction (shelters_to_create - num_predictionshelters)
      let num_create_prediction (shelters_to_create - num_create_not_prediction)
      ask n-of num_create_prediction (shelters with [prediction = True]) [set prediction False set size 4]
      ; these are created here:
      set shelters_to_create num_create_not_prediction
  ] ]

    ;;;if future-modus is false, but not prediction-accuracy = 100:

  ;;;;;;;;;;;;;;;;;;;;;;;;;; tot hier is het nieuwe deel.
  while [(count shelters) < (countshelters + shelters_to_create)] [ ; shelters are created one-by-one, to mimic reality better.
    set kansje kansje with [available >= 1]
    set kansje kansje with [count shelters-here = 0]
    let options kansje with [shelters in-radius (radius * 1.5) != nobody] ;Decide: include this in the create-shelters loop or keep it here.
    ask options [set numneighb (count shelters in-radius (radius)) ]

    create-shelters 1 [
      set shape "campsite"
      set size 4
      set covered? False
      set sick? False
      ifelse future-modus = True [ set prediction True] [set prediction False]
      set-preferences

      let best-location min-one-of options [location-utility]
      move-to best-location

      let current-available ([available] of patch-here)
      ask patches in-radius (0.5 * radius) [set available (available - 1) ]
      ask patches in-radius 3 [set available 0]
      if current-available > 1 [ask patch-here [set available 0.5]] ; This makes this still an option for facilities
      set available-here ([available] of patch-here)
        ]
    ]
    set ticks-last-count ticks
  ]

end

to-report location-utility ; this may only have patch-related variables
  let dummy 0
  ifelse is-list? distHF
    [ set dummy item 0 distHF ]
  [set dummy distHF ]
  report ( ( distHF-pref * dummy) + (distRoad-pref * distRoad) - (distneighb-pref * numneighb) )
end

to set-preferences
  ask shelters [
    set distRoad-pref random-normal Pr1:Road-proximity 1
    set distneighb-pref random-normal Pr2:Neighbour-proximity 1
    set distHF-pref random-normal Pr3:Healthcare-proximity 1
  ]
end

to test-setup-camp
    while [ticks < 6 ] [ ; after 6 weeks, this process stops.
    set shelters_to_create((random-normal ( pop_max / 12 ) ( pop_max / 18 ))) ; the real one would be: ( pop_max / 6 ) ( pop_max / 12 )))
    create-shelters shelters_to_create
    [
      set shape "campsite"
      set size 4
      set covered? False
      set sick? False
      set prediction False
      set-preferences

      ifelse count shelters >= 60 ;any? shelters ; if no shelters exist yet, all distHF values are 0.
        [let options kansje with [shelters in-radius (radius * 2) != nobody]
         let locations options with [available >= 1]
          ask locations [set numneighb (count shelters in-radius (radius * 1.5))] ;[any? shelters in-radius 5];
          set locations locations
         let best-location min-one-of locations [location-utility ] ;with [shelters in-radius 5 != nobody]); any? shelters in-radius 5

          move-to best-location
          let current-available ([available] of patch-here)
          ask patches in-radius (radius * 0.5) [set available (available - 1) ]
          ask patches in-radius 3 [set available 0]
          if current-available > 1 [ask patch-here [set available 0.5]] ; This makes this still an option for facilities
          set available-here ([available] of patch-here) ]

      [let locations kansje with [ available >= 1]
        let best-location one-of locations with-max [elevation]
       ;let best-location one-of locations with-min [( distRoad-pref * distRoad)];([patch-utility-for-refugee]); Rank list by neighbors first?)
        move-to best-location
        let current-available ([available] of patch-here)
        ask patches in-radius (radius * 0.5) [set available (available - 1) ]
        ask patches in-radius 3 [set available 0]
        if current-available > 1 [ask patch-here [set available 0.5]] ; This makes this still an option for facilities
        set available-here ([available] of patch-here)]
    ]
    tick
    ]
  ask shelters [
    set available-here ([available] of patch-here)
  ]
end

  to setup-camp-sep2017 ;; In 6 ticks (6 weeks) the camp is set up, representing the growth starting Aug 2017 until half of Sep 2017 (based on IOM's NPMs 1-7).
  ;; Bij voorkeur, doe dit van ticks -6 tot 0, zodat bij tick 1 het model normaal kan beginnen.
  while [ticks < 6] [ ; after 6 weeks, this process stops.
    set kansje patch-set patches with [pcolor != black and elevation >= 8.5]

  ;; First Hakimpara (camp 14) (by Oct 2017 5274 households)
    create-shelters 10 [;(random-normal ((5274 / 100) / 12 ) (((5274 / 100) / 36))) * ticks [

    set shape "campsite"
    set size 1
      set covered? False
      move-to max-one-of kansje [elevation]
      ;move-to one-of kansje
  ]
;  ;; Then, Jamtoli (camp 15) (aby Oct 2017 10936 households)
;    create-shelters 10 [;(random-normal ((10936 / 100) / 12) (((10936 / 100) / 36))) * ticks [
;
;    set shape "campsite"
;    set size 1
;      move-to one-of kansje
;  ]
;  ;; Lastly, Potibonia (camp 16) (avg #people/hh is 5.02 (NPM6))
;    create-shelters 10 [;(random-normal ((4269 / 100) / 12) (((4269 / 100) / 36))) * ticks [
;
;    set shape "campsite"
;    set size 1
;      move-to one-of kansje
;  ]
  tick
  ]
  patches-availability
  ask shelters [ set available-here ([available] of patch-here) ]

end

  ;; To give a (single) chance to find a better spot: (Not used now)
to move-toward-elevation
  let ahead [elevation] of patch-ahead 2
  let myright [elevation] of patch-right-and-ahead 30 2 ;; check in a range of 30 degrees and two patches distance what the elevation is.
  let myleft [elevation] of patch-left-and-ahead 30 2
  ifelse ((myright > ahead) and (myright > myleft)) ;; if patches to the right are higher, then turn and move in this direction.
      [ rt random 30  fd 2]
   [ if (myleft > ahead) ;; if patches to the left are higher, then turn and move in this direction
      [ lt random 30 fd 2]
    ]
  if [available] of patch-here < 0 [fd 1 move-toward-elevation]
end

to create-random-facilities ;; To make the model usable, because reading the real locations doesn't work yet:

  ;; The next 3 rules are also in PyNetlogo, should might be removed here.
  let count-facilities (count facilities)
  let count-shelters (count shelters)
  if count-facilities / count-shelters <= ( 1 / initial-capacity ) [ ; =21.86 because of SPHERE standard: 1 health post per 10.000 people. (10.000 / 100 / hh size (4.57) )

    create-facilities facilities_to_create [
      set shape "house"
      set size 5
      set color (blue - 0.6)
      move-to one-of kansje
      set capacity initial-capacity ; 22 (SPHERE standard = 1:10.000, so here it is 10.000/100/hh-size (4.57) = 21,861 = 22)
  ]
  ask shelters with [sick? = False] [
    ask my-out-links [die] ]
;  link-facility-shelters
  ]
set counter 0
end



 ;;;;;;; Link facilities and shelters ;;;;;;;
;to old-link-facility-shelters
;  ask shelters [
;    if (count my-out-links) = 0 [
;      ; add: if not using healthcare at the moment:
;      ; ask links [die]
;
;    ifelse [capacity] of min-one-of facilities [distance myself] > 0 [
;      create-link-with min-one-of facilities [distance myself] [set color green]
;      set covered? true
;
;     ;; let the connection also depend on available capacity.
;      ;; idea: change color of shelter when it is unlinked.
;    ask link-neighbors [set capacity (capacity - 1) ]
;  ]
;  [set covered? false
;   create-link-with min-one-of facilities [distance myself]
;      ask link-neighbors [set overcapacity (overcapacity + 1)] ]
;  ] ]
;
;  ; determine distance to facility:
;ask links [ set travel link-length ]
;ask shelters [set dist-HF ([travel] of my-out-links )
;    let x dist-HF
;    ask patch-here [set distHF x]]
; foreach sort-on [dist-HF] shelters [print "hey"]
;;  foreach sort-by [dist-HF] shelters
;end

to link-facility-shelters
  ask shelters [
    ifelse sick? = False [ask my-out-links [die]] [ask my-out-links [set color violet] ]]
    ; only violet links remain (for healthcare users), all others die.

  ask shelters [ if (count my-out-links) = 0 [ ; if a shelter has no link anymore, create a new one:
      create-link-to min-one-of facilities [distance myself] ]]
  after-linking-facility-shelters
end

to link-facility-realshelters
  ask shelters with [prediction = False] [
    ifelse sick? = False [ask my-out-links [die]] [ask my-out-links [set color violet] ]]
    ; only violet links remain (for healthcare users), all others die.

  ask shelters [ if (count my-out-links) = 0 [ ; if a shelter has no link anymore, create a new one:
      create-link-to min-one-of facilities [distance myself] ]]
  after-linking-facility-realshelters
end

to after-linking-facility-shelters
    ask links [ set travel link-length ]
    ask shelters [set dist-HF ([travel] of my-out-links )
    let x dist-HF
    ask patch-here [set distHF x]]

    ask facilities [
    set capacity initial-capacity
    set overcapacity 0
    let m (count my-in-links)
    let o (count my-in-links with [color = violet])
    ifelse m >= initial-capacity
    [ask min-n-of initial-capacity my-in-links [travel] [set color green] ]
    [ask my-in-links [set color green]]]
  ask links with [color = green] [
    ask end1 [set covered? True]
    ask end2 [set capacity (capacity - 1)] ]
  ask links with [color = grey] [
    ask end1 [set covered? False]
    ask end2 [set overcapacity (overcapacity + 1)] ]
end

to after-linking-facility-realshelters
    ask links [ set travel link-length ]
  ask shelters with [prediction = False] [set dist-HF ([travel] of my-out-links )
    let x dist-HF
    ask patch-here [set distHF x]]

    ask facilities [
    set capacity initial-capacity
    set overcapacity 0
    let m (count my-in-links)
    let o (count my-in-links with [color = violet])
    ifelse m >= initial-capacity
    [ask min-n-of initial-capacity my-in-links [travel] [set color green] ]
    [ask my-in-links [set color green]]]
  ask links with [color = green] [
    ask end1 [set covered? True]
    ask end2 [set capacity (capacity - 1)] ]
  ask links with [color = grey] [
    ask end1 [set covered? False]
    ask end2 [set overcapacity (overcapacity + 1)] ]
end


;;;;;;;; RUNNING THE SIMULATION ;;;;;;;

to go
  if future-modus = False [
  ifelse (count facilities) < 1 [user-message (word "There is no point in starting the simulation, because there are no facilities yet!") ]
  [ ;here comes everything you do if (count facilities > 0):
    set countshelters (count shelters with [prediction = False])
    set shelters_to_create random ((pop_max - countshelters) / 4 ) ; 2 ; yet to define
     ifelse shelters_to_create <= 0 [; if shelters_to_create is negative, you only want to use-health-facilities
      use-health-facilities
      ; you don't have to make new links, cause there is nothing new to link.
      ]
      ;else, you create shelters:
      [ create-new-shelters
        link-facility-shelters
        use-health-facilities] ]
;      [
;    create-new-shelters
;
;    link-facility-shelters
;
;    use-health-facilities      ; use health facilities
;    ]
                              ;; Decide: because first use-health-facilities and then create-new-facilities: new facilities are only being used after 1 week.

;;;; the next part will run in the normal model, but not in the PyNetlogo model ;;;;;

;    if counter = 4 [ ;;;; the next part will run in the normal model, but not in the PyNetlogo model)
;
;      let count-facilities (count facilities)
;      let count-shelters (count shelters)
;
;      if count-facilities / count-shelters <= ( 1 / initial-capacity ) [ ; =21.86 because of SPHERE standard: 1 health post per 10.000 people. (10.000 / 100 / hh size (4.57) )
;        create-random-facilities
;        ask shelters with [sick? = False] [
;          ask my-out-links [die] ]
;        link-facility-shelters ]
;      set counter 0
;    ]
  ]

  ;;;; to report:
  set average-distance (mean [travel] of links)
  let realshelters (shelters with [ prediction = False])
  set covered-shelters (count realshelters with [covered? = True])
  set sumshelters (count realshelters)
  set sumwaiting-patients (sum([waiting-patients] of facilities))
  set sumovercapacity (sum([overcapacity] of facilities))
  set unusedcapacity (sum([capacity] of facilities))
    if future-modus = False [
      set predicted-shelters (count shelters with [prediction = True])
;    ]
      ;  if future-modus = "False"[
  tick
  define-pop-max
;  set counter (counter + 1)
    if ticks = 94 [stop] ]
end

to use-health-facilities
  ask shelters with [prediction = False] [
    ifelse sick? = True [
      ; Check whether still sick, otherwise release consult-space:
      let p-healthy random-float 1
      if p-healthy >=  chance-remain-sick [
        set sick? False
        ask link-neighbors [
          set in-consult (in-consult - 1)
          if waiting-patients > 0 [
            set waiting-patients (waiting-patients - 1)
            set in-consult (in-consult + 1)
            set consultations (consultations + 1)
        ] ]
    ] ]
    ; if sick? = False:
    [
    let p-sick random-float 1
;    if p-sick <= 0.075714357 [ ; this is the avg amount of consults in 2019 divided by number of refugees.
    if p-sick <= chance-get-sick [ ; this is the avg amount of consults in 2019 divided by number of refugees multiplied by 4.57 (approx number of people in 1 hh).
;      use healthcare
      set sick? True
        ifelse (item 0 [in-consult] of link-neighbors) < 4 [
            ask link-neighbors [
;            ifelse in-consult < 4 [ ;4 is chosen because of average number of consults per facility, divided by 100.
              set in-consult (in-consult + 1)
              set consultations (consultations + 1)] ]
           ; else look for another facility:
          [ ifelse any? facilities with [in-consult < 4] [
            ask my-out-links [die]
            let alternatives facilities with [in-consult < 4]
            let alternative min-one-of alternatives [ distance myself]
            create-link-to alternative; max-one-of alternative [ distance myself]
;          print("I switched to another facility")
          after-linking-facility-shelters
          ask link-neighbors [
              set in-consult (in-consult + 1)
              set consultations (consultations + 1)]
          ]
;            let alternative (min-n-of 2 facilities [distance myself])
;            if in-consult of (max-one-of alternative [distance myself]) < 4[
;              create-link-with max-one-of alternative [distance myself]
;

          [ ask link-neighbors [set waiting-patients (waiting-patients + 1) ]]
      ]
  ]]]
end

to define-pop-max
  ;; this assumes that ticks are not reset after the first 6 setup ticks.
  ; first for number of people / hh-size at that moment:
;  if ticks = 10 [ set pop_max (818 / 	4.53478)] ; corresponds to November 2017
;  if ticks = 27 [ set pop_max (996 / 4.42689)] ; corresponds to March 2018
;  if ticks = 35 [ set pop_max (985 / 4.436028)] ; corresponds to May 2018
;  if ticks = 44 [ set pop_max (980 / 4.43271)] ; corresponds to July 2018
;  if ticks = 53 [ set pop_max (1044 / 4.42089)] ; corresponds to September 2018
;  if ticks = 61 [ set pop_max (1071 / 4.8503)] ; corresponds to November 2018
;  if ticks = 65 [ set pop_max (1077 / 4.47136)] ; corresponds to December 2018
;  if ticks = 74 [ set pop_max (1032 / 4.46254)] ; corresponds to February 2019
;  if ticks = 91 [set pop_max (1091 / 4.51434)] ; corresponds to June 2019

  ; for number of households at that moment.
  if ticks = 10 [ set pop_max 180 * pop_max_SA] ; corresponds to November 2017
  if ticks = 27 [ set pop_max 225 * pop_max_SA] ; corresponds to March 2018
  if ticks = 35 [ set pop_max 222 * pop_max_SA] ; corresponds to May 2018
  if ticks = 44 [ set pop_max 221 * pop_max_SA] ; corresponds to July 2018
  if ticks = 53 [ set pop_max 236 * pop_max_SA] ; corresponds to September 2018
  if ticks = 61 [ set pop_max 221 * pop_max_SA] ; corresponds to November 2018
  if ticks = 65 [ set pop_max 241 * pop_max_SA] ; corresponds to December 2018
  if ticks = 74 [ set pop_max 231 * pop_max_SA] ; corresponds to February 2019
  if ticks = 91 [set pop_max 242 * pop_max_SA] ; corresponds to June 2019
end



;;;; Old go command ;;;;
;to go
;  ; First, the end numbers are defined. These are from RRRC, February 28 2019, which is 75 weeks from the start of the simulation (mid September 2017).
;  set countshelters ( list (count shelters with [campnr = 14]) (count shelters with [campnr = 15]) (count shelters with [campnr = 16]) )
;
;
;;  ifelse reception-center = true
;;    [ go-through-reception ] ;when the switch of reception-centre is on, then refugees are being allocated by a central organization.
;;    [ settle-randomly ]      ;else, they choose a location themselves, with very limited knowledge of facilities.
;;
;  tick
;end


;;;;;; Used to set-up the initial background ;;;;;;
to first-setup
  ;; Part of original setup, but replaced by 'import-world' command:
  gis:load-coordinate-system (word "data/WGS_84_Geographic.prj")
  set elevation-dataset gis:load-dataset "data/3_regions_asc_good.asc" ; file that contains the elevation of camps 14, 15, 16.
  show-elevation-in-patches
end

to display-elevation ; this only displays the elevation. No data is stored within the patches.
  gis:paint elevation-dataset 0
end

to show-elevation-in-patches
  ; This applies the raster dataset to the patches in the Netlogo environment,
  ; and stores the elevation data in the patches in one step using gis:apply-raster.
 ; gis:apply-raster elevation-dataset elevation
  ; To color the patches according to their elevation, we color them:
  let min-elevation gis:minimum-of elevation-dataset
  let max-elevation gis:maximum-of elevation-dataset
  ask patches [
    set elevation gis:raster-sample elevation-dataset self
    ; to filter out NaNs, the following line is added:
    if (elevation <= 0) or (elevation >= 0) [
      set pcolor scale-color green elevation min-elevation max-elevation ]
    if pcolor = black [set elevation 0]
  ]
end


 ;;;;;; Command to draw the roads ;;;;;;
 ;; Idea is: draw the roads once, then export them and import them in the setup when necessary in a model.
 ;; So don't draw again each time.
to draw-roads
  ifelse mouse-down?
    [ if not any? drawers                 ;; creates a new drawer at the beginning of a stroke
        [ create-drawers 1 [
        set size 8
        set pen-size 1.5
        set xcor mouse-xcor
        set ycor mouse-ycor
;        set path []
        pen-down
        set color 125 ] ]
      ask drawers [ follow-mouse ] ]      ;; updates paths of drawers as long as the mouse button is down
    [ ask drawers [ become-tracer ] ]     ;; completes the stroke and turns drawers into tracers
  ask tracers [ die ]
end

to follow-mouse
  let x mouse-xcor                    ;; gets the current mouse coordinates
  let y mouse-ycor
  facexy x y
  setxy x y
;  set path fput (list x y) path       ;; adds the coordinate pair (x,y) to the front of the path
end

to become-tracer
  set breed tracers
  pen-up
 end


;;;;;;; NOT USED ;;;;;;;

;;; this is a try to read the location of shelters:
;to read-shelter-time-to-facility; Reads the locations of facilities to use in the simulation.
;  file-close-all; closes all open files
;  if not file-exists? "data/TimeDistanceColors.csv" [
;    user-message "No file 'TimeDistanceColors' exists!"
;    stop
;  ]
;  file-open "data/TimeDistanceColors.csv" ; opens the file with the facility location data
;  while [ not file-at-end? ] [ ; all data will be read in a continuous loop
;  let data csv:from-row file-read-line
;  create-facilities 1 [
;      let x item 1 data ; third column holds the latitude of the facilities (corrected for the width of the coordinates over 500 patches).
;      ;set xcor ((x - 20.5909772) / 0.0026969034250262)
;      set xcor x
;      let y item 2 data ; fourth column holds the longitude of the facilities (corrected for the width of the coordinates over 500 patches).
;    ;set ycor ((y - 0.246537875076936) / 0.00269690342502619)
;      let z item 4 data
;    set ycor y
;      set size 10
;    set color z
;  ]
;  ]
;file-close
;end


;to read-facilities-from-csv ; Reads the locations of facilities to use in the simulation.
;  file-close-all; closes all open files
;  if not file-exists? "data/HealthFacilitiesScaled.csv" [
;    user-message "No file 'HealthFacilitiesScaled' exists!"
;    stop
;  ]
;  file-open "data/HealthFacilitiesScaled.csv" ; opens the file with the facility location data
;  while [ not file-at-end? ] [ ; all data will be read in a continuous loop
;  let data csv:from-row file-read-line
;  create-facilities 1 [
;      let x item 1 data ; third column holds the latitude of the facilities (corrected for the width of the coordinates over 500 patches).
;      ;set xcor ((x - 20.5909772) / 0.0026969034250262)
;      set xcor x
;      let y item 2 data ; fourth column holds the longitude of the facilities (corrected for the width of the coordinates over 500 patches).
;    ;set ycor ((y - 0.246537875076936) / 0.00269690342502619)
;    set ycor y
;      set size 10
;    set color blue
;  ]
;  ]
;file-close
;ask shelters [ update-coverage ]
;end
@#$#@#$#@
GRAPHICS-WINDOW
187
10
606
430
-1
-1
2.045
1
10
1
1
1
0
0
0
1
0
200
0
200
0
0
1
ticks
30.0

BUTTON
13
19
76
52
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
13
101
136
134
NIL
create-random-facilities
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

PLOT
616
12
856
162
Number of households
ticks
#Households
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"Jamtoli" 1.0 0 -2674135 true "" "plot count shelters with [campnr = 14]"
"Hakimpara" 1.0 0 -13840069 true "" "plot count shelters with [campnr = 15]"
"Potibonia" 1.0 0 -13345367 true "" "plot count shelters with [campnr = 16]"
"# shelters" 1.0 0 -7500403 true "" "plot count shelters with [prediction = False]"

SWITCH
657
562
808
595
reception-center
reception-center
0
1
-1000

BUTTON
91
19
154
52
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

CHOOSER
657
475
803
520
space-standard
space-standard
"SPHERE standard" "5m2 per person" "10m2 per person"
0

BUTTON
721
310
825
343
NIL
draw-roads
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
230
464
336
497
NIL
link-facility-shelters
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SWITCH
657
525
821
558
random-settlement
random-settlement
0
1
-1000

SLIDER
0
196
172
229
Pr1:Road-proximity
Pr1:Road-proximity
1
10
1.0
1
1
NIL
HORIZONTAL

SLIDER
0
232
185
265
Pr2:Neighbour-proximity
Pr2:Neighbour-proximity
1
10
1.0
1
1
NIL
HORIZONTAL

SLIDER
0
268
188
301
Pr3:Healthcare-proximity
Pr3:Healthcare-proximity
1
10
1.0
1
1
NIL
HORIZONTAL

TEXTBOX
3
180
153
198
Refugee preferences:
11
0.0
1

TEXTBOX
5
394
155
412
Actor preferences:
11
0.0
1

SLIDER
-1
411
171
444
Pr4:Road-proximity
Pr4:Road-proximity
1
10
0.0
1
1
NIL
HORIZONTAL

SLIDER
-2
448
176
481
Pr5:Increase-coverage
Pr5:Increase-coverage
1
10
0.0
1
1
NIL
HORIZONTAL

SLIDER
0
484
172
517
Pr6:Center-of-people
Pr6:Center-of-people
1
10
0.0
1
1
NIL
HORIZONTAL

BUTTON
340
464
483
497
NIL
create-new-shelters
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
340
430
429
463
NIL
reset-ticks
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
616
169
737
214
Ticks until new facilities
counter
17
1
11

MONITOR
616
218
680
263
pop_max
pop_max
4
1
11

MONITOR
616
267
717
312
Total consultations
consultations
17
1
11

BUTTON
239
430
336
463
NIL
test-setup-camp
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
683
218
797
263
NIL
mean [travel] of links
4
1
11

BUTTON
13
137
139
170
NIL
ask shelters [die]
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

CHOOSER
617
349
856
394
space-usage
space-usage
"current situation (22m2/person)" "improvement target (35m2/person" "SPHERE standard (45m2/person)"
0

BUTTON
13
61
110
94
NIL
setup-world
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

campsite
false
0
Polygon -7500403 true true 150 11 30 221 270 221
Polygon -16777216 true false 151 90 92 221 212 221
Line -7500403 true 150 30 150 225

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.0.4
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
