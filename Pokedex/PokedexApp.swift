//
//  PokedexApp.swift
//  Pokedex
//
//  Created by Leif on 10/18/22.
//

import CacheStore
import SwiftUI

@main
struct PokedexApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView(
                    store: Store(
                        initialValues: [
                            .pokemonIndex: 1,
                            .favorites: [
                                "bulbasaur",
                                "gengar"
                            ]
                        ],
                        actionHandler: pokedexActionHandler,
                        dependency: .live
                    )
                    .debug
                )
            }
        }
    }
}
