port module PhotoGroove exposing (main)

import Browser
import Html exposing (..)
import Html.Attributes as Attr exposing (class, classList, id, name, src, title, type_)
import Html.Events exposing (on, onClick)
import Http
import Json.Decode exposing (Decoder, at, int, list, string, succeed)
import Json.Decode.Pipeline exposing (optional, required)
import Json.Encode as Encode
import Random

urlPrefix : String
urlPrefix =
    "http://elm-in-action.com/"

type Msg
    = ClickedPhoto String
    | ClickedSize ThumbnailSize
    | ClickedSupriseMe
    | GotRandomPhoto Photo
    | GotActivity String
    | GotPhotos (Result Http.Error (List Photo))
    | SlidHue Int
    | SlidRipple Int
    | SlidNoise Int

view : Model -> Html Msg
view model =
    div [ class "content" ] <|
        case model.status of
            Loaded photos selectedUrl ->
                viewLoaded photos selectedUrl model
            Loading ->
                []
            Errored errorMessage ->
                [ text ("Error: " ++ errorMessage) ]

viewLoaded : List Photo -> String -> Model -> List (Html Msg)
viewLoaded photos selectedUrl model =
    [ h1 [] [ text "Photo Groove" ]
    , button
        [ onClick ClickedSupriseMe ]
        [ text "Suprise Me" ]
    , div [ class "activity" ] [ text model.activity ]
    , div [ class "filters" ]
        [ viewFilter SlidHue "Hue" model.hue
        , viewFilter SlidRipple  "Ripple" model.ripple
        , viewFilter SlidNoise "Noise" model.noise
        ]
    , h3 [] [ text "Thumbnail Size:" ]
    , div [ id "choose-size" ]
        (List.map viewSizeChooser [ Small, Medium, Large ])
    , div [ id "thumbnails", class (sizeToString model.chosenSize) ]
        (List.map (viewThumbnail selectedUrl) photos)
    , canvas [ id "main-canvas", class "large" ] []
    ]

viewSizeChooser : ThumbnailSize -> Html Msg
viewSizeChooser size =
    label []
        [ input [ type_ "radio", name "size", onClick (ClickedSize size) ] []
        , text (sizeToString size)
        ]

viewThumbnail : String -> Photo -> Html Msg
viewThumbnail selectedUrl thumb =
    img
        [ src (urlPrefix ++ thumb.url)
        , title (thumb.title ++ " [" ++ String.fromInt thumb.size ++ " KB]")
        , classList [ ("selected", selectedUrl == thumb.url) ]
        , onClick (ClickedPhoto thumb.url)
        ]
        []

viewFilter : (Int -> Msg) -> String -> Int -> Html Msg
viewFilter toMsg name magnitude =
    div [ class "filter-slider" ]
        [ label [] [ text name ]
        , rangeSlide
            [ Attr.max "11"
            , Attr.property "val" (Encode.int magnitude)
            , onSlide toMsg
            ]
            []
        , label [] [ text (String.fromInt magnitude) ]
        ]

rangeSlide : List (Attribute msg) -> List (Html msg) -> Html msg
rangeSlide attributes children =
    node "range-slider" attributes children

sizeToString : ThumbnailSize -> String
sizeToString size =
    case size of
        Small ->
            "small"
        Medium ->
            "med"
        Large ->
            "large"

onSlide : (Int -> msg) -> Attribute msg
onSlide toMsg =
    at [ "detail", "userSlideTo" ] int
        |> Json.Decode.map toMsg
        |> on "slide"

type alias FilterOptions =
    { url : String
    , filters : List { name : String, amount : Float }
    }

port setFilters : FilterOptions -> Cmd msg

port activityChanges : (String -> msg) -> Sub msg

applyFilters : Model -> (Model, Cmd Msg)
applyFilters model =
    case model.status of
        Loaded _ selectedUrl ->
            let
                filters =
                    [ { name = "Hue", amount = toFloat model.hue / 11 }
                    , { name = "Ripple", amount = toFloat model.ripple / 11 }
                    , { name = "Noise", amount = toFloat model.noise / 11 }
                    ]
                url =
                    urlPrefix ++ "large/" ++ selectedUrl
            in
            (model, setFilters { url = url, filters = filters })
        Loading ->
            (model, Cmd.none)
        Errored _ ->
            (model, Cmd.none)

type alias Photo =
    { url : String
    , size  : Int
    , title : String
    }

photoDecoder : Decoder Photo
photoDecoder =
    succeed Photo
        |> required "url" string
        |> required "size" int
        |> optional "title" string "(untitled)"

type ThumbnailSize
    = Small
    | Medium
    | Large

type Status
    = Loading
    | Loaded (List Photo) String
    | Errored String

type alias Model =
    { status : Status
    , activity : String
    , chosenSize : ThumbnailSize
    , hue : Int
    , ripple : Int
    , noise : Int
    }

initialModel : Model
initialModel =
    { status = Loading
    , activity = ""
    , chosenSize = Medium
    , hue = 5
    , ripple = 5
    , noise = 5
    }


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
    case msg of
        ClickedPhoto url ->
            applyFilters { model | status = selectUrl url model.status }
        ClickedSupriseMe ->
            case model.status of
                Loaded [] _ ->
                    (model, Cmd.none)
                Loaded (firstPhoto :: otherPhotos) _ ->
                    Random.uniform firstPhoto otherPhotos
                        |> Random.generate GotRandomPhoto
                        |> Tuple.pair model
                Loading ->
                    (model, Cmd.none)
                Errored _ ->
                    (model, Cmd.none)
        ClickedSize size ->
            ({ model | chosenSize = size }, Cmd.none)
        GotRandomPhoto photo ->
            applyFilters { model | status = selectUrl photo.url model.status }
        GotPhotos (Ok photos) ->
            case photos of
                (firstPhoto :: _) ->
                    applyFilters { model | status = Loaded photos firstPhoto.url }
                [] ->
                    ({ model | status = Errored "0 photos found" }, Cmd.none)
        GotPhotos (Err _) ->
            ({ model | status = Errored "Server error!" }, Cmd.none)
        SlidHue hue ->
            applyFilters { model | hue = hue }
        SlidRipple ripple ->
            applyFilters { model | ripple = ripple }
        SlidNoise noise ->
            applyFilters { model | noise = noise }
        GotActivity activity ->
            ({ model | activity = activity }, Cmd.none)

selectUrl : String -> Status -> Status
selectUrl url status =
    case status of
        Loaded photos _ ->
            Loaded photos url
        Loading ->
            status
        Errored _ ->
            status

initialCmd : Cmd Msg
initialCmd =
    Http.get
        { url = "http://elm-in-action.com/photos/list.json"
        , expect = Http.expectJson GotPhotos (list photoDecoder)
        }


main : Program Float Model Msg
main =
    Browser.element
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }

init : Float -> (Model, Cmd Msg)
init flags =
    let
        activity =
            "Initializing Pasta v" ++ String.fromFloat flags
    in
    ({ initialModel | activity = activity }, initialCmd)

subscriptions : Model -> Sub Msg
subscriptions _ =
    activityChanges GotActivity
