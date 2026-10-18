"""Board selection shared by planner + renderer.

In "auto" mode the teacher moves between boards like a real classroom:
notebook for definitions, graph board for diagrams, chalkboards for
explanations, whiteboard for examples and quizzes.
"""

SCENE_BOARDS = {
    "intro": "green_board",
    "objectives": "white_board",
    "concept": "ruled_board",
    "explanation": "black_board",
    "diagram": "graph_board",
    "reading": "white_board",
    "notes": "ruled_board",
    "example": "white_board",
    "worked_example": "graph_board",
    "mistakes": "ruled_board",
    "summary": "green_board",
    "quiz": "white_board",
    "revision": "black_board",
}

BOARD_THEME_NAMES = ["auto", "green_board", "black_board", "white_board",
                     "dark_board", "light_board", "ruled_board", "graph_board"]
