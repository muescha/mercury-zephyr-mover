# encoding: UTF-8

require 'pp'

require File.expand_path('../config.rb', __FILE__)

require @zephryos_path

#API.log @root_path
#API.log @memory_file
#API.log @zephryos_path

require 'yaml'



# ----------------------------------------
# Constants
# ----------------------------------------

@state = nil
@active = false
@help_active = false

@mash = ['cmd', 'alt', 'ctrl']

# my settings from mercury mover
#no modifier 100pixel
#shift 1 pixel
#option 10 pixel
#control 10 pixel

@move_weight = {0 => 1, 1 => 10, 2=>50, 3 => 100}
@move_mods = {
    3 => [],
    2 => ['cmd'],
    1 => ['alt', 'cmd'],
    0 => ['alt']
}

@move_dir = {
    'UP' => [0, -1],
    'DOWN' => [0, 1],
    'LEFT' => [-1, 0],
    'RIGHT' => [1, 0]
}

@states = {
    'UP' => :move,
    'DOWN' => nil,
    'RIGHT' => :resize_bottom_right,
    'LEFT' => :resize_top_left
}

@arrows = {
    :move => '', #✢
    :resize_bottom_right => '⇲',
    :resize_top_left => '⇱'
}


# ----------------------------------------
# Patch some files
# ----------------------------------------

class Rect
  def description
    "x:#{x} y:#{y} w:#{w} h:#{h}"
  end
end

class API
  class << self
    def log(*args)
      args.each do |arg|
        #pp arg
      end
      #STDOUT.flush
    end
  end
end


# ----------------------------------------
# File operations
# ----------------------------------------

def read_memory
  memory = File.exists?(@memory_file) ? YAML.load(File.read(@memory_file))||{} : {}
  API.log memory.to_yaml
  memory
end

def save_memory(memory)
  File.open @memory_file, 'w' do |file|
    file.puts memory.to_yaml
  end
end


# ----------------------------------------
# Window Moving Shortcuts
# ----------------------------------------

def unbind_window_moving

  @state = nil

  @move_mods.each do |weight, mods|
    @move_dir.each do |dir, direction|
      API.unbind dir, mods
    end
  end
end

def bind_window_moving
  @move_mods.each do |weight, mods|
    @move_dir.each do |key, direction|
      API.bind key, mods do
        manipulate key, direction, weight
        state_info
      end
    end
  end
end


# ----------------------------------------
# Window frame Manipulations
# ----------------------------------------

def manipulate(key, direction, weight)

  API.log "#{@state} #{key}, #{direction}, #{weight}"

  case (@state)
    when :move
      manipulate_move direction, weight
    when :resize_top_left
      manipulate_top_left direction, weight
    when :resize_bottom_right
      manipulate_bottom_right direction, weight
    else
      API.log 'none'
  end
end

def manipulate_move(direction, weight)
  manipulate_frame do |frame|
    frame.x += direction[0]*@move_weight[weight]
    frame.y += direction[1]*@move_weight[weight]
    frame
  end
end

def manipulate_top_left(direction, weight)
  manipulate_frame do |frame|
    frame.x += direction[0]*@move_weight[weight]
    frame.w -= direction[0]*@move_weight[weight]
    frame.y += direction[1]*@move_weight[weight]
    frame.h -= direction[1]*@move_weight[weight]
    frame
  end
end

def manipulate_bottom_right(direction, weight)
  manipulate_frame do |frame|
    frame.w += direction[0]*@move_weight[weight]
    frame.h += direction[1]*@move_weight[weight]
    frame
  end
end

def manipulate_frame(&blk)
  win = API.focused_window
  frame = win.frame
  API.log frame
  frame = blk.call(frame) if blk
  API.log frame
  win.frame = frame
end



# ----------------------------------------
# Direction Selector
# ----------------------------------------

def unbind_mercury_zephyr_mover_states
  unbind_window_moving

  @states.each do |key, state|
    API.unbind key, @mash
  end

end

def bind_mercury_zephyr_mover_states
  @states.each do |key, state|
    API.bind key, @mash do
      unbind_window_moving
      @state = state
      state ? bind_window_moving : unbind_window_moving
      state_info
    end
  end
end


# ----------------------------------------
# Memory
# ----------------------------------------

def unbind_memory
  unbind_read_memory
  unbind_set_memory
  unbind_select_memory
  unbind_delete_memory
end

def bind_memory
  bind_read_memory
  bind_set_memory
  bind_select_memory
  bind_delete_memory
end


# ----------------------------------------
# save current window
# ----------------------------------------

def unbind_set_memory
  API.unbind 'return', @mash
end

def bind_set_memory
  API.bind 'RETURN', @mash do

    unbind_window_moving

    state_info 'Save to Memory:'

    memory = read_memory

    list = ('A'..'Z').map { |key| "#{key}: #{memory[key].nil? ? '' : memory[key].description}" }

    frame = API.focused_window.frame

    unbind_escape

    API.choose_from list, "Save to Memory #{frame.description}", 10, 50 do |list_index|

      if list_index
        key = list[list_index][0]

        memory[key] = frame

        unbind_read_memory
        save_memory memory
        bind_read_memory

        API.alert "Saved Window to key #{key} for #{frame.description}"
        API.log memory.to_yaml
      end

      state_info
      stop_mercury_zephyr_mover
    end

  end
end


# ----------------------------------------
# select frame from memory
# ----------------------------------------

def unbind_select_memory
  API.unbind 'TAB', @mash
end

def bind_select_memory
  API.bind 'TAB', @mash do

    unbind_window_moving

    state_info 'Select from Memory:'
    memory = read_memory

    list = memory.map { |key, frame| "#{key}: #{frame.description}" }

    unbind_escape

    API.choose_from list, 'Select from Memory', 10, 100 do |list_index|

      if list_index
        frame = memory[list[list_index][0]]
        API.alert "Set Window to #{frame.description}"

        manipulate_frame { frame }
      end

      state_info
      stop_mercury_zephyr_mover
    end
  end
end


# ----------------------------------------
# delete moemory
# ----------------------------------------

def unbind_delete_memory
  API.unbind 'DELETE', @mash
end

def bind_delete_memory
  API.bind 'DELETE', @mash do

    unbind_window_moving

    state_info 'Delete from Memory:'
    memory = read_memory

    list = memory.map { |key, frame| "#{key}: #{frame.description}" }

    unbind_escape

    API.choose_from list, 'Delete from Memory', 10, 100 do |list_index|

      if list_index
        key = list[list_index][0]

        memory.delete key

        unbind_read_memory
        save_memory memory
        bind_read_memory

        API.log memory.to_yaml
        API.alert "Delete Window for key #{key}"
      end

      state_info
      stop_mercury_zephyr_mover
    end
  end
end

# ----------------------------------------
# create shortcuts for saved windows
# ----------------------------------------

def unbind_read_memory
  memory = read_memory
  memory.each do |key, frame|
    API.unbind key, @mash
  end
end

def bind_read_memory
  memory = read_memory
  memory.each do |key, frame|
    API.bind key, @mash do
      manipulate_frame { frame }
      API.alert "Set Window to #{frame.description}"
      stop_mercury_zephyr_mover
    end
  end
end


# ----------------------------------------
#resize all child windows
# ----------------------------------------

def unbind_resize_child_windows
  API.unbind "\\", @mash
end

# Mars Mover General

def bind_resize_child_windows
  API.bind "\\", @mash do
    win = API.focused_window
    frame = win.frame
    API.log frame
    app = win.app
    visible_windows = app.visible_windows
    windows_count = visible_windows.size
    state_info "Resize 0 of #{windows_count}"
    counter = 0
    visible_windows.each do |child_win|
      counter += 1
      state_info "Resize #{counter} of #{windows_count}"
      API.log child_win.title
      child_win.frame = frame
    end
    state_info
    API.alert "Set all child window to #{frame.description}"
    stop_mercury_zephyr_mover
  end
end

# exit with escape

def unbind_escape
  API.unbind 'ESCAPE', []
end

def bind_escape
  API.bind 'ESCAPE', [] do
    stop_mercury_zephyr_mover
  end 
end


# ----------------------------------------
# Help
# ----------------------------------------

def unbind_help
  API.unbind '.', @mash
  @help_active = false
end

def bind_help
  API.bind '.', @mash do

    if @help_active
      API.hide_box
      @help_active = false
    else
      @help_active = true

      API.show_box "" +

"MercuryZephyrMover: Help

    Activate: ctrl+alt+cmd+/
    Exit    : ctrl+alt+cmd+/ or ESC

    Help      : ctrl+alt+cmd+.

    Apply to all Child windows: ctrl+alt+cmd+\\

    Select Movement Direction:

        ctrl+alt+cmd+↑ : Move
        ctrl+alt+cmd+←: resize top left
        ctrl+alt+cmd+→: resize bottom right
        ctrl+alt+cmd+↓ : disable movement

        Movement shortcuts: modifier + direction
            modifier:
                       none = 100px
                       cmd =  50px
                alt+cmd =  10px
                alt          =   1px
            direction: ( ↑ ← → ↓)

    Memory:

        Shortcuts:
            Save    : ctrl+alt+cmd+return
            Select  : ctrl+alt+cmd+tab
            Delete : ctrl+alt+cmd+delete
            Use     : ctrl+alt+cmd+[saved key]

        Memory file (settings in file 'zephyros/config.rb'):

            #{@memory_file}"
    end
  end
end


##########################################
# Main
##########################################

def stop_mercury_zephyr_mover
  unbind_mercury_zephyr_mover_states
  unbind_resize_child_windows
  unbind_memory
  unbind_help
  unbind_escape
  API.hide_box
  API.alert 'MercuryZephyrMover: Turn Off'
  @active = false
end

def start_mercury_zephyr_mover
  API.alert "MercuryZephyrMover: Start \n\nPress CTRL+ALT+CMD+. for Help"
  state_info
  bind_mercury_zephyr_mover_states
  bind_resize_child_windows
  bind_memory
  bind_help
  bind_escape
  @active = true
end

def state_info(state = 'Ready')
  API.show_box "MercuryZephyrMover: #{state} #{(@state.nil? ? '' : @arrows[@state]).to_s} (#{API.focused_window.frame.description})"
end


##########################################
#
# Mercury Zyphyr Mover:Main Entry Point
#
##########################################

API.bind '/', @mash do
  API.log 'go'
  if @active
    stop_mercury_zephyr_mover
  else
    start_mercury_zephyr_mover
  end
end

API.log 'Relaunched Script'

wait_on_callbacks
