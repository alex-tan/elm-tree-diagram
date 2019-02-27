module TreeDiagram exposing
    ( Tree, node
    , Coord, Drawable, NodeDrawer, EdgeDrawer, draw_
    , TreeLayout, defaultTreeLayout, TreeOrientation, leftToRight, rightToLeft, bottomToTop, topToBottom
    )

{-| This library provides functions drawing diagrams of trees.


# Building a tree

@docs Tree, node


# Drawing a tree

@docs Coord, Drawable, NodeDrawer, EdgeDrawer, draw_


# Tree layout options

@docs TreeLayout, defaultTreeLayout, TreeOrientation, leftToRight, rightToLeft, bottomToTop, topToBottom

-}


{-| A tree data structure
-}
type Tree a
    = Node a (List (Tree a))


{-| Direction of the tree from root to leaves
-}
type TreeOrientation
    = LeftToRight
    | RightToLeft
    | TopToBottom
    | BottomToTop


{-| 2D coordinate
-}
type alias Coord =
    ( Float, Float )


type alias Contour =
    List ( Int, Int )


{-| Alias for functions that draw nodes
-}
type alias NodeDrawer a fmt =
    a -> fmt


{-| Alias for functions that draw edges between nodes
-}
type alias EdgeDrawer fmt =
    Coord -> fmt


{-| Functions for moving around and composing drawings
-}
type alias Drawable fmt out =
    { position : Coord -> fmt -> fmt
    , compose : Int -> Int -> List fmt -> out
    , transform : Int -> Int -> Coord -> Coord
    }


type alias PositionedTree a =
    Tree ( a, Coord )


type alias PrelimPosition =
    { subtreeOffset : Int
    , rootOffset : Int
    }


{-| Options to be passed to `draw_` for laying out the tree:

  - orientation: direction of the tree from root to leaves.
  - levelHeight: vertical distance between parent and child nodes.
  - subtreeDistance: horizontal distance between subtrees.
  - siblingDistance: horizontal distance between siblings. This is usually set
    below `subtreeDistance` to produce a clearer distinction between sibling
    nodes and non-siblings on the same level of the tree.
  - padding: amount of space to leave around the edges of the diagram.

-}
type alias TreeLayout =
    { orientation : TreeOrientation
    , levelHeight : Int
    , siblingDistance : Int
    , subtreeDistance : Int
    , padding : Int
    }


{-| A set of default values that should be modified to create your TreeLayout
-}
defaultTreeLayout : TreeLayout
defaultTreeLayout =
    { orientation = TopToBottom
    , levelHeight = 100
    , siblingDistance = 50
    , subtreeDistance = 80
    , padding = 40
    }


{-| Constructs a tree out of a root value and a list of subtrees
-}
node : a -> List (Tree a) -> Tree a
node val children =
    Node val children


{-| Draws the tree using the provided functions for drawings nodes and edges.
TreeLayout contains some more options for positioning the tree.
-}
draw_ : Drawable fmt out -> TreeLayout -> NodeDrawer a fmt -> EdgeDrawer fmt -> Tree a -> out
draw_ drawer layout drawNode drawLine tree =
    let
        positionedTree =
            position layout tree
    in
    drawPositioned drawer layout.padding drawNode drawLine positionedTree


{-| Function for assigning the positions of a tree's nodes.
The value returned by this function is a tuple of the positioned tree, and
the dimensions the tree occupied by the positioned tree.
-}
position : TreeLayout -> Tree a -> PositionedTree a
position layout tree =
    let
        ( prelimTree, _ ) =
            prelim layout.siblingDistance layout.subtreeDistance tree

        finalTree =
            final 0 layout.levelHeight 0 prelimTree

        ( width, height ) =
            treeBoundingBox finalTree

        {- The right hand side of the leftmost node ends with a negative position in `pairwiseSubtreeOffset` since its
        contour is (0, 0) and the next is something like (400, 400). This results in the position being -300
        (difference - siblingDistance). This will show up as the left side going into the padding (or disappearing
        entirely) and the right side moving further away from the padding.

        Our solution is to translate all nodes on their final transformation to ensure they all appear in the diagram.
        This is considered "good enough" whereas a real solution owuld probably result in a large rework of `prelim`.
        This works for my layout (where `siblingDistance` and `subtreeDistance` are 100).
        -}
        finalOffset =
            toFloat layout.siblingDistance * 3

        transform =
            \( x, y ) ->
                case layout.orientation of
                    LeftToRight ->
                        ( y - height / 2, x - width / 2 + finalOffset )

                    RightToLeft ->
                        ( -y + height / 2, x - width / 2 + finalOffset )

                    BottomToTop ->
                        ( x - width / 2 + finalOffset, y - height / 2 )

                    TopToBottom ->
                        ( x - width / 2 + finalOffset, -y + height / 2 )
    in
    treeMap (\( v, coord ) -> ( v, transform coord )) finalTree


{-| Function for drawing an already-positioned tree.
-}
drawPositioned : Drawable fmt out -> Int -> NodeDrawer a fmt -> EdgeDrawer fmt -> PositionedTree a -> out
drawPositioned drawer padding drawNode drawLine positionedTree =
    let
        ( width, height ) =
            treeBoundingBox positionedTree

        totalWidth =
            round width + 2 * padding

        totalHeight =
            round height + 2 * padding
    in
    drawer.compose
        totalWidth
        totalHeight
        (drawInternal
            totalWidth
            totalHeight
            drawer
            drawNode
            drawLine
            positionedTree
        )


{-| Finds the smallest box that fits around the positioned tree
-}
treeBoundingBox : PositionedTree a -> ( Float, Float )
treeBoundingBox tree =
    let
        ( ( minX, maxX ), ( minY, maxY ) ) =
            treeExtrema tree
    in
    ( maxX - minX, maxY - minY )


{-| Find the min and max X and Y coordinates in the positioned tree
-}
treeExtrema : PositionedTree a -> ( ( Float, Float ), ( Float, Float ) )
treeExtrema (Node ( _, ( x, y ) ) subtrees) =
    let
        extrema =
            List.map treeExtrema subtrees

        ( xExtrema, yExtrema ) =
            List.unzip extrema

        ( minXs, maxXs ) =
            List.unzip xExtrema

        ( minYs, maxYs ) =
            List.unzip yExtrema

        minX =
            min x <| Maybe.withDefault x <| List.minimum minXs

        maxX =
            max x <| Maybe.withDefault x <| List.maximum maxXs

        minY =
            min y <| Maybe.withDefault y <| List.minimum minYs

        maxY =
            max y <| Maybe.withDefault y <| List.maximum maxYs
    in
    ( ( minX, maxX ), ( minY, maxY ) )


{-| Helper function for recursively drawing the tree.
-}
drawInternal : Int -> Int -> Drawable fmt out -> NodeDrawer a fmt -> EdgeDrawer fmt -> PositionedTree a -> List fmt
drawInternal width height drawer drawNode drawLine (Node ( v, rootCoord ) subtrees) =
    let
        transRootCoord =
            drawer.transform width height rootCoord

        ( transRootX, transRootY ) =
            transRootCoord

        subtreePositions =
            List.map (\(Node ( _, coord ) _) -> coord) subtrees

        transSubtreePositions =
            List.map (drawer.transform width height) subtreePositions

        subtreeOffsetsFromRoot =
            List.map
                (\( transSubtreeX, transSubtreeY ) ->
                    ( transSubtreeX - transRootX, transSubtreeY - transRootY )
                )
                transSubtreePositions

        rootDrawing =
            drawNode v |> drawer.position transRootCoord

        edgeDrawings =
            List.map (\coord -> drawLine coord |> drawer.position transRootCoord)
                subtreeOffsetsFromRoot
    in
    List.append
        (List.append edgeDrawings [ rootDrawing ])
        (List.concatMap (drawInternal width height drawer drawNode drawLine) subtrees)


{-| Assign the final position of each node within the the input tree. The final
positions are found by performing a preorder traversal of the tree and
summing up the relative positions of each node's ancestors as the traversal
moves down the tree.
-}
final : Int -> Int -> Int -> Tree ( a, PrelimPosition ) -> PositionedTree a
final level levelHeight lOffset (Node ( v, prelimPosition ) subtrees) =
    let
        finalPosition =
            ( toFloat (lOffset + prelimPosition.rootOffset)
            , toFloat (level * levelHeight)
            )

        -- Preorder recursion into child trees
        subtreePrelimPositions =
            List.map
                (\(Node ( _, prelimPosition_ ) _) -> prelimPosition_)
                subtrees

        visited =
            List.map2
                (\prelimPos subtree ->
                    final
                        (level + 1)
                        levelHeight
                        (lOffset + prelimPos.subtreeOffset)
                        subtree
                )
                subtreePrelimPositions
                subtrees
    in
    Node ( v, finalPosition ) visited


{-| Assign the preliminary position of each node within the input tree. The
preliminary positions are found by performing a postorder traversal on the
tree and aligning each subtree relative to its parent. Sibling subtrees are
pushed together as close to each other as possible, and parent nodes are
positioned so that they're centered over their children.
-}
prelim : Int -> Int -> Tree a -> ( Tree ( a, PrelimPosition ), Contour )
prelim siblingDistance subtreeDistance (Node val children) =
    let
        -- Traverse each of the subtrees, getting the positioned subtree as well as
        -- a description of its contours.
        visited =
            List.map (prelim siblingDistance subtreeDistance) children

        ( subtrees, childContours ) =
            List.unzip visited

        -- Calculate the position of the left bound of each subtree, relative to
        -- the left bound of the current tree.
        offsets =
            subtreeOffsets siblingDistance subtreeDistance childContours

        -- Store the offset for each of the subtrees.
        updatedChildren =
            List.map2
                (\(Node ( v, prelimPosition ) children_) offset ->
                    Node ( v, { prelimPosition | subtreeOffset = offset } ) children_
                )
                subtrees
                offsets
    in
    case ends <| List.map2 (\a b -> ( a, b )) updatedChildren childContours of
        -- The root of the current tree has children.
        Just ( ( lSubtree, lSubtreeContour ), ( rSubtree, rSubtreeContour ) ) ->
            let
                (Node ( _, lPrelimPos ) _) =
                    lSubtree

                (Node ( _, rPrelimPos ) _) =
                    rSubtree

                -- Calculate the position of the root, relative to the left bound of
                -- the current tree. Store this in the preliminary position for the
                -- current tree.
                prelimPos =
                    { subtreeOffset = 0
                    , rootOffset = rootOffset lPrelimPos rPrelimPos
                    }

                -- Construct the contour description of the current tree.
                rootContour =
                    ( prelimPos.rootOffset, prelimPos.rootOffset )

                treeContour =
                    rootContour
                        :: buildContour
                            lSubtreeContour
                            rSubtreeContour
                            rPrelimPos.subtreeOffset
            in
            ( Node ( val, prelimPos ) updatedChildren, treeContour )

        -- The root of the current tree is a leaf node.
        Nothing ->
            ( Node ( val, { subtreeOffset = 0, rootOffset = 0 } ) updatedChildren
            , [ ( 0, 0 ) ]
            )


{-| Reduce a list from the left, building up all of the intermediate results into a list.
scanl (+) 0 [1,2,3,4] == [0,1,3,6,10]
-}
scanl : (a -> b -> b) -> b -> List a -> List b
scanl f b xs =
    let
        scan1 x accAcc =
            case accAcc of
                acc :: _ ->
                    f x acc :: accAcc

                [] ->
                    []

        -- impossible
    in
    List.reverse (List.foldl scan1 [ b ] xs)


{-| Given the preliminary positions of leftmost and rightmost subtrees, this
calculates the offset of the root (their parent) relative to the leftmost
bound of the tree starting at the root.
-}
rootOffset : PrelimPosition -> PrelimPosition -> Int
rootOffset lPrelimPosition rPrelimPosition =
    (lPrelimPosition.subtreeOffset
        + rPrelimPosition.subtreeOffset
        + lPrelimPosition.rootOffset
        + rPrelimPosition.rootOffset
    )
        // 2


{-| Calculate how far each subtree should be offset from the left bound of the
first (leftmost) subtree. Each subtree needs to be positioned so that it is
exactly `subtreeDistance` away from its neighbors.
-}
subtreeOffsets : Int -> Int -> List Contour -> List Int
subtreeOffsets siblingDistance subtreeDistance contours =
    case List.head contours of
        Just c0 ->
            let
                cumulativeContours =
                    scanl
                        (\c ( aggContour, _ ) ->
                            let
                                offset =
                                    pairwiseSubtreeOffset
                                        siblingDistance
                                        subtreeDistance
                                        aggContour
                                        c
                            in
                            ( buildContour aggContour c offset, offset )
                        )
                        ( c0, 0 )
                        (List.drop 1 contours)
            in
            List.map (\( _, runningOffset ) -> runningOffset) cumulativeContours

        Nothing ->
            []


{-| Given two contours, calculate the offset of the second from the left bound
of the first such that the two are separated by exactly `minDistance`.
-}
pairwiseSubtreeOffset : Int -> Int -> Contour -> Contour -> Int
pairwiseSubtreeOffset siblingDistance subtreeDistance lContour rContour =
    let
        levelDistances =
            List.map2
                (\( _, lTo ) ( rFrom, _ ) -> lTo - rFrom)
                lContour
                rContour
    in
    case List.maximum levelDistances of
        Just separatingDistance ->
            let
                minDistance =
                    if
                        List.length lContour
                            == 1
                            || List.length rContour
                            == 1
                    then
                        siblingDistance

                    else
                        subtreeDistance
            in
            separatingDistance + minDistance

        Nothing ->
            0


{-| Construct a contour for a tree. This is done by combining together the
contours of the leftmost and rightmost subtrees, and then adding the root
at the top of the new contour.
-}
buildContour : Contour -> Contour -> Int -> Contour
buildContour lContour rContour rContourOffset =
    let
        lLength =
            List.length lContour

        rLength =
            List.length rContour

        combinedContour =
            List.map2
                (\( lFrom, lTo ) ( rFrom, rTo ) ->
                    ( lFrom, rTo + rContourOffset )
                )
                lContour
                rContour
    in
    if lLength > rLength then
        List.append combinedContour (List.drop rLength lContour)

    else
        List.append
            combinedContour
            (List.map
                (\( from, to ) -> ( from + rContourOffset, to + rContourOffset ))
                (List.drop lLength rContour)
            )


{-| Left-to-right tree orientation
-}
leftToRight : TreeOrientation
leftToRight =
    LeftToRight


{-| Right-to-left tree orientation
-}
rightToLeft : TreeOrientation
rightToLeft =
    RightToLeft


{-| Top-to-bottom tree orientation
-}
topToBottom : TreeOrientation
topToBottom =
    TopToBottom


{-| Bottom-to-top tree orientation
-}
bottomToTop : TreeOrientation
bottomToTop =
    BottomToTop


{-| Create a tuple containing the first and last elements in a list

    ends [ 1, 2, 3, 4 ] == ( 1, 4 )

-}
ends : List a -> Maybe ( a, a )
ends list =
    let
        first =
            List.head list

        last =
            List.head <| List.reverse list
    in
    Maybe.map2 (\a b -> ( a, b )) first last


{-| Apply a function to the value of each node in a tree to produce a new tree.
-}
treeMap : (a -> a) -> Tree a -> Tree a
treeMap fn (Node v children) =
    Node (fn v) (List.map (treeMap fn) children)
