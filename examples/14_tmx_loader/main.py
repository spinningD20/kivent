from kivy.app import App
from kivy.core.window import Window
from kivy.clock import Clock
from kivy.uix.widget import Widget
from kivy.properties import StringProperty
from kivent_core.systems.gamesystem import GameSystem
from kivent_core.managers.resource_managers import texture_manager
from os.path import dirname, join, abspath
from kivent_maps import map_utils
from kivent_maps.map_system import MapSystem

Window.size = (640, 640)


def get_asset_path(asset, asset_loc):
    return join(dirname(dirname(abspath(__file__))), asset_loc, asset)


class Game(Widget):
    def __init__(self, **kwargs):
        super(Game, self).__init__(**kwargs)
        self.map_list = ['orthogonal.tmx', 'ortho2.tmx', 'ortho3.tmx']
        self.index = 0
        self.do_map_init()
        # Init gameworld with all the systems
        self.gameworld.init_gameworld(
            ['position', 'color', 'camera1', 'tile_map'] + self.map_layers + self.map_layer_animators,
            callback=self.init_game)

    def do_map_init(self):
        # Args required for Renderer init
        map_render_args = {
            'zones': ['general'],
            'frame_count': 2,
            'gameview': 'camera1',
            'shader_source': get_asset_path('positionshader.glsl', 'assets/glsl')
        }
        # Args for AnimationSystem init
        map_anim_args = {
            'zones': ['general'],
        }
        # Args for PolyRenderer init
        map_poly_args = {
            'zones': ['general'],
            'frame_count': 2,
            'gameview': 'camera1',
            'shader_source': 'poscolorshader.glsl'
        }

        # Initialise systems for 4 map layers and get the renderer and
        # animator names
        self.map_layers, self.map_layer_animators = \
            map_utils.load_map_systems(6, self.gameworld,
            map_render_args, map_anim_args,
            map_poly_args)
        # r, a = map_utils.load_map_systems(6, self.gameworld, map_render_args, map_anim_args, map_poly_args)
        # self.map_layers = r + a
        # Set the camera1 render order to render lower layers first
        self.camera1.render_system_order = reversed(self.map_layers)

    def init_game(self):
        self.setup_states()
        self.setup_tile_map('orthogonal.tmx')
        self.set_state()

    def setup_tile_map(self, map_name):
        # The map file to load
        # Change to hexagonal/isometric/isometric_staggered.tmx for other maps
        filename = get_asset_path(map_name,'assets/maps')
        map_manager = self.gameworld.managers['map_manager']

        # Load TMX data and create a TileMap from it
        map_name = map_utils.parse_tmx(filename, self.gameworld)

        # Initialise each tile as an entity in the gameworld
        map_utils.init_entities_from_map(map_manager.maps[map_name], self.gameworld.init_entity)
        self.tilemap = map_manager.maps[map_name]

    def setup_states(self):
        # We want renderers to be added and unpaused
        # and animators to be unpaused
        self.gameworld.add_state(state_name='main',
                systems_added=self.map_layers + self.map_layer_animators,
                systems_unpaused=self.map_layers + self.map_layer_animators)

    def set_state(self):
        self.gameworld.state = 'main'

    def screen_touched(self, event):
        self.index += 1
        self.gameworld.clear_entities()
        for layer in self.map_layers + self.map_layer_animators:
            self.gameworld.system_manager[layer].clear_entities()
        self.gameworld.systems_to_add = []
        self.setup_tile_map(self.map_list[self.index % 3])


class DebugPanel(Widget):
    fps = StringProperty(None)

    def __init__(self, **kwargs):
        super(DebugPanel, self).__init__(**kwargs)
        Clock.schedule_once(self.update_fps)

    def update_fps(self,dt):
        self.fps = str(int(Clock.get_fps()))
        Clock.schedule_once(self.update_fps, .05)


class YourAppNameApp(App):
    pass


if __name__ == '__main__':
    YourAppNameApp().run()
