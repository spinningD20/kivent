from kivent_core.rendering.model cimport VertexModel
from kivent_core.rendering.vertex_formats cimport VertexFormat2F4UB
from kivent_core.rendering.animation cimport FrameList
from kivent_core.managers.resource_managers import texture_manager
from kivent_core.memory_handlers.block cimport MemoryBlock
from kivent_maps.map_manager cimport MapManager


cdef class LayerTile:
    '''
    A LayerTile represents data for one layer of a Tile. It stores informtion
    required to render this layer of the tile.
    
    **Attributes**:
        **model** (str): Name of the model used by this LayerTile
        
        **texture** (str): Name of the texture used by this LayerTile

        **animation** (str): Name of the animation used by this LayerTile or
        None if this LayerTile is not animated.

        **layer** (unsigned int): layer index of this LayerTile.

    **Attributes: (Cython Access Only)**
        **tile_pointer** (TileStruct*): Pointer to a TileStruct which stores
        data required by the attributes.

        **model_manager** (ModelManager): Instance of the gameworld's
        ModelManager to get vertex model pointer from model name.

        **animation_manager** (AnimationManager): Instance of the gameworld's
        AnimationManager to get animation data pointer from animation name.

    '''

    def __cinit__(self, 
                  ModelManager model_manager, 
                  AnimationManager animation_manager, 
                  unsigned int layer):
        self.model_manager = model_manager
        self.animation_manager = animation_manager
        self.layer = layer

    property model:
        def __get__(self):
            cdef VertexModel model = <VertexModel>self.tile_pointer.model
            return model.name

        def __set__(self, value):
            self.tile_pointer.model = <void*>self.model_manager.models[value]

    property texture:
        def __get__(self):
            return texture_manager.get_texname_from_texkey(self.tile_pointer.texkey)

        def __set__(self, value):
            self.tile_pointer.texkey = texture_manager.get_texkey_from_name(value)

    property animation:
        def __get__(self):
            cdef FrameList animation
            if self.tile_pointer.animation != NULL:
                animation = <FrameList>self.tile_pointer.animation
                return animation.name
            else:
                return False

        def __set__(self, str value):
            if value is not None:
                self.tile_pointer.animation = <void*>self.animation_manager.animations[value]
            else:
                self.tile_pointer.animation = NULL

    property layer:
        def __get__(self):
            return self.layer


cdef class Tile:
    '''
    A Tile is a collection of LayerTiles for one grid position on the map.
    The LayerTiles hold data for idividual layers and collectively form one
    Tile. Multiple Tiles arranged on the grid form the TileMap.

    **Attributes: (Cython Access Only)**
       **model_manager** (ModelManager): Gameworld's ModelManager instance to
       pass to LayerTiles while initialising them.

       **animation_manager** (AnimationManager): Gameworld's AnimationManager
       instance to pass to LayerTiles while initialising them.

       **layer_count** (unsigned int): The maximum number of layers this Tile
       can hold i.e. the size of the TileStruct array.

       **_layers** (TileStruct*): Pointer to TileStruct array which holds data
       for each layer of this tile. Size of this array is given by layer_count.

    **Attributes:**
        **layers** (list): List of LayerTiles contained in this tile. The list
        only contains a LayerTile for the non-empty layers so the list size may
        be less than layer_count.

    '''

    def __cinit__(self, ModelManager model_manager,
                  AnimationManager animation_manager,
                  unsigned int layer_count):
        self.model_manager = model_manager
        self.animation_manager = animation_manager
        self.layer_count = layer_count

    def get_layer_tile(self, unsigned int layer):
        '''
        Returns a LayerTile object for the given layer.

        Args:
            layer (unsigned int): The layer for which to return the LayerTile.

        '''

        tile = LayerTile(self.model_manager, self.animation_manager, layer)
        tile.tile_pointer = &(self._layers[layer])

        return tile

    property layers:
        def __get__(self):
            l = []
            cdef LayerTile tile

            for i in range(self.layer_count):
                tile = LayerTile(self.model_manager, self.animation_manager, i)
                tile.tile_pointer = &(self._layers[i])                    

                # Check if the struct has data or is empty
                if (tile.tile_pointer.model != NULL 
                    or tile.tile_pointer.animation != NULL):
                    l.append(tile)
            return l


cdef class LayerObject:
    '''
    LayerObject is a non-tile object on the map. The types of LayerObject are
    polygons, ellipses and images. To render a LayerObject we require the
    render data (model and color/texture) and position.

    **Attributes:**
        **model** (VertexModel): The vertex model to render for this object.
        If it is a polygon/ellipse this model will contain the vertices data
        for those shapes.

        **texture** (str): Name of the texture used. This will be set only if
        the LayerObject is an image else will be None.

        **position** (tuple): Position as (x,y) of the first vertex inside this
        Object's VertexModel, x being distance from left-edge and y being
        distance from top-edge.

        **layer** (unsigned int): Layer in which the object is.

        **color** (tuple): Color of the Object if it is a shape. This color
        data is taken from the first vertex of its VertexModel.

    '''

    def __cinit__(self, ModelManager model_manager):
        self.model_manager = model_manager

    property model:
        def __get__(self):
            cdef VertexModel model = <VertexModel>self.obj_pointer.model
            return model.name

        def __set__(self, value):
            self.obj_pointer.model = <void*>self.model_manager.models[value]

    property texture:
        def __get__(self):
            if self.obj_pointer.texkey > 0:
                return texture_manager.get_texname_from_texkey(
                                            self.obj_pointer.texkey)
            else:
                return None

        def __set__(self, value):
            self.obj_pointer.texkey = texture_manager \
                                        .get_texkey_from_name(value)

    property position:
        def __get__(self):
            return (self.obj_pointer.x, self.obj_pointer.y)
        def __set__(self, value):
            self.obj_pointer.x = value[0]
            self.obj_pointer.y = value[1]

    property layer:
        def __get__(self):
            return self.layer

    property color:
        def __get__(self):
            cdef VertexModel model = <VertexModel>self.obj_pointer.model
            cdef VertexFormat2F4UB* vertex = \
                    <VertexFormat2F4UB*>model.vertices_block.data
            return (vertex.v_color[0], vertex.v_color[1], 
                    vertex.v_color[2], vertex.v_color[3])


cdef class TileMap:
    '''
    A TileMap holds all tile data for each location of the map grid for each
    layer, and a list of arbitrarily positioned LayerObjects.
    The tiles in this TileMap will be orthogonal.

    Render data for tiles is stored as a contiguous array of TileStructs.
    If the map size is M rows, N columns and L layers then the array dimensions
    are [M][N][L]. Each location (i,j) has a 1D array of size [L] which can be
    interfaced using Tile object. Each TileStruct inside that 1D array is
    interfaced using LayerTile.

    **Attributes:**
        **tiles** (list): 2D array of Tile objects representing every grid
        grid location on the map. To set the tile data provide it a 2D array of
        a list of dicts in the format

        .. code-block:: python

            tiles[i][j] = \
                    [{
                        'model': 'model-name',
                        'texture': 'texture-name',
                        'layer': 1,
                    },
                    {
                        'animation': 'animation-name',
                        'layer': 2,
                    }]

        The 'layer' is zero indexed and layers for which there is no dict in
        this list are left empty.

        **objects** (list): 2D list of LayerObjects on the map, separated
        by layer. To set data for these pass a 2D list of dicts of the format

        .. code-block:: python

            objects[layer] = \
                    [{
                        'model': 'model-name',
                        'texture': texture-name',
                        'position': (x, y)
                    }]

        **z_index_map** (list): List of ints which maps layer index of tiles
        and objects to z index i.e. render order for that layer. While
        initialising entities from this TileMap use this z_index_map to
        get which system to add the entity to given the layer index.
        Values till tile_layer_count correspond to tile layers and after that
        to object layers.

        **size** (tuple): Size of the grid i.e. (rows, cols)

        **size_on_screen** (tuple): Size in pixels when displayed on the screen

        **tile_size** (tuple): Size in pixels of one tile image

        **name** (str): Name of this TileMap

    '''

    def  __cinit__(self, unsigned int size_x, unsigned int size_y,
                   unsigned int tile_layer_count, unsigned int object_count,
                   MemoryBlock tile_buffer,
                   ModelManager model_manager,
                   AnimationManager animation_manager,
                   str name):
        self.size_x = size_x
        self.size_y = size_y
        self.tile_layer_count = tile_layer_count
        self.object_count = object_count
        self.name = name
        self.model_manager = model_manager
        self.animation_manager = animation_manager

        cdef MemoryBlock tiles_block = MemoryBlock(
            size_x * size_y * tile_layer_count * sizeof(TileStruct), 
            tile_layer_count * sizeof(TileStruct), 1)
        tiles_block.allocate_memory_with_buffer(tile_buffer)
        self.tiles_block = tiles_block

        cdef MemoryBlock objects_block = MemoryBlock(
            object_count * sizeof(ObjStruct), 
            sizeof(ObjStruct), 1)
        objects_block.allocate_memory_with_buffer(tile_buffer)
        self.objects_block = objects_block

    def __dealloc__(self):
        if self.tiles_block is not None:
            self.tiles_block.remove_from_buffer()
            self.tiles_block = None
        if self.objects_block is not None:
            self.objects_block.remove_from_buffer()
            self.objects_block = None

    def get_tile(self, unsigned int x, unsigned int y, bint empty=False):
        '''
        Get a Tile at (i,j) grid position of the tile map from TileStruct array

        Args:
            x (unsigned int): row of the tile

            y (unsigned int): col of the tile

            empty (boolean): Will set NULL to the pointers in all the
            TileStructs if True. Default False.

        Return:
            Tile: contains data of TileStruct array

        '''
        if x >= self.size_x and y >= self.size_y:
            raise IndexError()

        cdef Tile tile = Tile(self.model_manager, self.animation_manager,
                                self.tile_layer_count)
        tile._layers = <TileStruct*>self.tiles_block.get_pointer(x*self.size_x + y)

        cdef TileStruct tile_data
        if empty:
            for i in range(self.tile_layer_count):
                tile_data = tile._layers[i]
                tile_data.model = NULL
                tile_data.texkey = 0
                tile_data.animation = NULL

        return tile

    def get_object(self, unsigned int n, bint empty=False):
        '''
        Get nth LayerObject in the map from ObjStruct. Because there is no
        fixed number of objects for each object layer, the objects are one
        big array and they are referenced by that index. The layer value
        is stored in the ObjStruct.

        Args:
            n (unssigned int): index of the object in the list

            empty (boolean): Will set NULL to the pointers in the ObjStructs
            if True. Default False.

        Return:
            LayerObject: containing data of the ObjStruct

        '''
        if n >= self.object_count:
            raise IndexError()

        cdef LayerObject obj = LayerObject(self.model_manager)
        obj_data = <ObjStruct*>self.objects_block.get_pointer(n)

        if empty:
            obj_data.model = NULL
            obj_data.texkey = 0

        obj.obj_pointer = obj_data
        return obj

    def free_memory(self):
        if self.tiles_block is not None:
            self.tiles_block.remove_from_buffer()
            self.tiles_block = None
        if self.objects_block is not None:
            self.objects_block.remove_from_buffer()
            self.objects_block = None

    def get_tile_position(self, unsigned int i, unsigned int j):
        '''
        Calculates the pixel position of the center of the tile
        at (i, j) grid position.

        Args:
            i (unsigned int): row of the tile

            j (unsigned int): col of the tile

        Return:
            (unsigned int, unsigned int): Pixel position of center as x,y
            where x is distance from left edge and y is from top edge.

        '''
        w, h = self.size_on_screen
        tw, th = self.tile_size

        return (j * tw + tw/2, h - i * th - th/2)

    property tiles:
        def __get__(self):
            tile_list = []
            for i in range(self.size_x):
                tile_row = []
                for j in range(self.size_y):
                    tile_row.append(self.get_tile(i,j))
                tile_list.append(tile_row)

        def __set__(self, list tiles):
            cdef unsigned int size_x = len(tiles)
            cdef unsigned int size_y = len(tiles[0])
            cdef FrameList frames

            if size_x != self.size_x or size_y != self.size_y:
                raise Exception(
                        "Provided tiles list does not match internal size")
            for i in range(size_x):
                for j in range(size_y):
                    tile_layers = self.get_tile(i,j, True)
                    layer_data = tiles[i][j]

                    for data in layer_data:
                        tile = tile_layers.get_layer_tile(data['layer'])
                        if 'animation' in data:
                            frames = self.animation_manager \
                                        .animations[data['animation']]
                            tile.animation = data['animation']

                            # Take initial data from first frame
                            tile.texture = frames[0].texture
                            tile.model = frames[0].model
                        else:
                            tile.texture = data['texture']
                            tile.model = data['model']

    property objects:
        def __set__(self, list objs):
            cdef unsigned int layers = len(objs)
            cdef unsigned int obj_count = 0
            cdef LayerObject obj

            self._obj_layers_index = []

            for i in range(layers):
                self._obj_layers_index.append(obj_count)

                for obj_data in objs[i]:
                    obj = self.get_object(obj_count, True)
                    if 'texture' in obj_data:
                        obj.texture = obj_data['texture']
                    obj.model = obj_data['model']
                    obj.position = obj_data['position']
                    obj.layer = i + self.tile_layer_count

                    obj_count += 1
            self.obj_layer_count = layers
            self._obj_layers_index.append(obj_count)
        def __get__(self):
            cdef unsigned int layer_size
            cdef unsigned int pos
            cdef LayerObject obj

            objs = []
            for i in range(self.obj_layer_count):
                obj_layer = []
                layer_size = (self._obj_layers_index[i+1] - 
                                self._obj_layers_index[i])

                for j in range(layer_size):
                    pos = self._obj_layers_index[i] + j
                    obj = self.get_object(pos)
                    obj.layer = i + self.tile_layer_count
                    obj_layer.append(obj)

                objs.append(obj_layer)
            return objs

    property z_index_map:
        def __get__(self):
            return self._z_index_map
        def __set__(self, list value):
            self._z_index_map = value

    property size:
        def __get__(self):
            return (self.size_x, self.size_y)

    property size_on_screen:
        def __get__(self):
            sx, sy = self.size_x, self.size_y
            tw, th = self.tile_size_x, self.tile_size_y

            return (sx * tw, sy * th)

    property tile_size:
        def __get__(self):
            return (self.tile_size_x, self.tile_size_y)
        def __set__(self, tuple value):
            self.tile_size_x = value[0]
            self.tile_size_y = value[1]

    property name:
        def __get__(self):
            return self.name

    
cdef class StaggeredTileMap(TileMap):
    '''
    StaggeredTileMap is a subclass of TileMap which is used for isometric
    staggered tile maps. It overrides the get_tile_position function
    and size_on_screen property because they are calculated differently
    for staggered tiles.

    Staggered tiles are arranged like this:

    .. code-block:: python

        ---------
         ---------
        ---------
         ---------

        or 

        | | | |
        |||||||
        |||||||
        |||||||
        |||||||
         | | |


    **Attributes:**
        **stagger_index** (str): indicates whether to shift even or odd
        tiles while staggering. Can take value 'even' or 'odd.

        **stagger_axis** (boolean): Whether to stagger along x or y axis.
        Can take values 'x' and 'y'.

    '''
    def get_tile_position(self, i, j):
        w, h = self.size_on_screen
        tw, th = self.tile_size
        sa = self._stagger_axis
        si = self._stagger_index

        if sa:
            # Staggered along x axis

            y = h - (i * th + th/2)
            x = (j * tw)/2 + tw/2

            # If tile's x index matches the stagger index
            # it needs to be shifted down on the y axis
            if si != ((j+1)%2 == 0):
                y -= th/2
        else:
            # Staggered along y axis

            y = h - ((i * th)/2 + th/2)
            x = j * tw + tw/2

            # If tile's y index matches the stagger index
            # it needs to be shifted right on the x axis
            if si != ((i+1)%2 == 0):
                x += tw/2

        return (x, y)

    property size_on_screen:
        def __get__(self):
            sx, sy = self.size_x, self.size_y
            tw, th = self.tile_size_x, self.tile_size_y
            sa = self._stagger_axis

            if sa: # x axis
                return ((sx - 1) * tw/2 + tw,
                        sy * th + th/2)
            else: # y axis
                return (sx * tw + tw/2,
                        (sy - 1) * th/2 + th)

    property stagger_index:
        def __get__(self):
            return 'even' if self._stagger_index else 'odd'
        def __set__(self, str value):
            self._stagger_index = value == 'even'

    property stagger_axis:
        def __get__(self):
            return 'x' if self._stagger_axis else 'y'
        def __set__(self, str value):
            self._stagger_axis = value == 'x'


cdef class HexagonalTileMap(StaggeredTileMap):
    '''
    HexagonalTileMap is for hexagonal tiles. Hexagonal tiles are like isometric
    tiles but with an extra flat length along width or height. They are also
    arranged in the staggered format.

    **Attributes:**
        **hex_side_length** (unsigned int): The side length of the hexagon in
        the tile. This turns out to be the same as considering an isometric
        tile lengthened along width/height. The extra length makes one side of
        the hexagon.

    '''
    def get_tile_position(self, i, j):
        w, h = self.size_on_screen
        tw, th = self.tile_size
        sa = self._stagger_axis
        si = self._stagger_index
        ts = self.hex_side_length

        if sa:
            y = h - (i * th + th/2)
            x = (j * (tw + ts))/2 + tw/2

            if si != ((j+1)%2 == 0):
                y -= th/2
        else:
            y = h - ((i * (th + ts))/2 + th/2)
            x = j * tw + tw/2

            if si != ((i+1)%2 == 0):
                x += tw/2

        return (x, y)

    property size_on_screen:
        def __get__(self):
            sx, sy = self.size_x, self.size_y
            tw, th = self.tile_size_x, self.tile_size_y
            sa = self._stagger_axis
            ts = self.hex_side_length 

            if sa:
                return ((sx - 1) * (tw + ts)/2 + tw,
                        sy * th + th/2)
            else:
                return (sx * tw + tw/2,
                        (sy - 1) * (th + ts)/2 + th)

    property hex_side_length:
        def __get__(self):
            return self.hex_side_length
        def __set__(self, unsigned int value):
            self.hex_side_length = value


cdef class IsometricTileMap(TileMap):
    '''
    IsometricTileMap is used to display isometric tiles in the isometric
    projection layout. It is a subclass of TileMap with different
    get_tile_position and size_on_screen.
    '''
    def get_tile_position(self, i, j):
        w, h = self.size_on_screen
        tw, th = self.tile_size

        x, y = ((j - i) * tw/2,
                (j + i) * th/2)

        x += w/2
        y = h - th/2 - y

        return (x, y)

    property size_on_screen:
        def __get__(self):
            s = max(self.size_x, self.size_y)
            tw, th = self.tile_size_x, self.tile_size_y

            return (s * tw, s * th)

