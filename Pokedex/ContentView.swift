//
//  ContentView.swift
//  Pokedex
//
//  Created by Leif on 10/18/22.
//

import c
import CacheStore
import SwiftUI

enum PokedexAPI {
    static let path: URL = URL(string: "https://pokeapi.co/api/v2/")!

    enum Route {
        static let pokemon: URL = PokedexAPI.path.appending(path: "pokemon")
    }
}

enum PokedexKey {
    enum PokemonJSONKey: String {
        enum SpritesKey: String {
            case front_default
        }

        enum TypesKey: String {
            case type
            case name, url
        }

        case name
        case sprites
        case types
    }

    case pokemonIndex
    case pokemonImage

    case favorites

    case pokemon
}

enum PokedexAction {
    case previousPokemon, nextPokemon, favoritePokemon

    case fetchPokemon, pokemonResponse(c.JSON<PokedexKey.PokemonJSONKey>)

    case loadImage(URL), imageResponse(UIImage)
}

struct PokedexEnvironment {
    var pokemonCount: Int

    var fetchPokemon: (Int) async throws -> c.JSON<PokedexKey.PokemonJSONKey>
}

let pokedexActionHandler: StoreActionHandler<PokedexKey, PokedexAction, PokedexEnvironment> = StoreActionHandler { cacheStore, action, environment in
    switch action {
    case .previousPokemon:
        cacheStore.update(.pokemonIndex, as: Int.self) { currentIndex  in
            guard
                let index = currentIndex,
                index > 1
            else { return }

            currentIndex? -= 1
        }

        return ActionEffect(.fetchPokemon)

    case .nextPokemon:
        cacheStore.update(.pokemonIndex, as: Int.self) { currentIndex in
            guard
                let index = currentIndex,
                index < environment.pokemonCount
            else { return }

            currentIndex? += 1
        }

        return ActionEffect(.fetchPokemon)

    case .fetchPokemon:
        let pokemonIndex = cacheStore.get(.pokemonIndex) ?? 0
        cacheStore.remove(.pokemonImage)
        return ActionEffect {
            .pokemonResponse((try? await environment.fetchPokemon(pokemonIndex)) ?? c.JSON(initialValues: [:]))
        }

    case let .pokemonResponse(pokemon):
        cacheStore.set(value: pokemon, forKey: .pokemon)

        guard
            let sprites = pokemon.json(.sprites, keyed: PokedexKey.PokemonJSONKey.SpritesKey.self),
            let spriteURLString: String = sprites.get(.front_default),
            let spriteURL = URL(string: spriteURLString)
        else { return .none }

        return ActionEffect(.loadImage(spriteURL))

    case let .loadImage(url):
        return ActionEffect {
            guard
                let (data, _) = try? await URLSession.shared.data(from: url),
                let image = UIImage(data: data)
            else { return .none }

            return .imageResponse(image)
        }

    case let .imageResponse(image):
        cacheStore.set(value: image, forKey: .pokemonImage)
        return .none

    case .favoritePokemon:
        let currentPokemon = cacheStore.resolve(.pokemon, as: c.JSON<PokedexKey.PokemonJSONKey>.self)
        cacheStore.update(
            .favorites,
            as: [String].self,
            updater: { favorites in
                let pokemonName = currentPokemon.resolve(.name, as: String.self)
                guard favorites != nil else {
                    favorites = [pokemonName]
                    return
                }

                if
                    let currentFavorites = favorites,
                    currentFavorites.contains(pokemonName)
                {
                    favorites?.removeAll(where: { $0 == pokemonName })
                } else {
                    favorites?.append(pokemonName)
                }
            }
        )

        return .none
    }
}

extension PokedexEnvironment {
    static var mock: PokedexEnvironment {
        PokedexEnvironment(
            pokemonCount: 9,
            fetchPokemon: { _ in
                c.JSON(initialValues: [.name: "mock gengar"])
            }
        )
    }

    static var live: PokedexEnvironment {
        PokedexEnvironment(
            pokemonCount: 1154,
            fetchPokemon: { pokemonIndex in
                let (data, _) = try await URLSession.shared.data(from: PokedexAPI.Route.pokemon.appending(path: "\(pokemonIndex)"))
                let json = c.JSON<PokedexKey.PokemonJSONKey>(data: data)
                return json
            }
        )
    }
}

struct ContentView: StoreView {
    struct Content: StoreContent {
        private let store: Store<PokedexKey, Void, Void>

        var pokemon: c.JSON<PokedexKey.PokemonJSONKey>? {
            store.get(.pokemon)
        }

        var name: String {
            pokemon?.get(.name) ?? ""
        }

        var image: UIImage? {
            store.get(.pokemonImage)
        }

        var pokemonTypes: [String]? {
            pokemon?.array(.types, keyed: PokedexKey.PokemonJSONKey.TypesKey.self)?
                .compactMap {
                    $0.json(.type, keyed: PokedexKey.PokemonJSONKey.TypesKey.self)?.get(.name, as: String.self)
                }
        }

        init(store: Store<PokedexKey, Void, Void>) {
            self.store = store
        }
    }

    @ObservedObject var store: Store<PokedexKey, PokedexAction, PokedexEnvironment>

    var body: some View {
        if content.pokemon != nil {
            VStack {
                // Info Views
                VStack {
                    if let jsonTypes = content.pokemonTypes {
                        HStack {
                            ForEach(jsonTypes, id: \.self) { type in
                                Text("\(type)".capitalized)
                            }
                        }
                    }

                    Spacer()

                    if let image = content.image {
                        Image(uiImage: image)
                            .resizable(resizingMode: .stretch)
                            .aspectRatio(contentMode: .fit)
                    } else {
                        ProgressView()
                    }

                    Spacer()
                }

                // Pokdex Controls
                VStack {
                    HStack {
                        Button(
                            action: { store.handle(action: .previousPokemon) },
                            label: {
                                Image(systemName: "arrow.backward.circle.fill")
                                    .font(.largeTitle)
                            }
                        )

                        Spacer()

                        Spacer()

                        Button(
                            action: { store.handle(action: .nextPokemon) },
                            label: {
                                Image(systemName: "arrow.forward.circle.fill")
                                    .font(.largeTitle)
                            }
                        )
                    }
                }
                .frame(height: 120)
            }
            .padding()
            .navigationTitle(content.name.capitalized)
            .toolbar {
                Button(
                    action: { store.handle(action: .favoritePokemon) },
                    label: {
                        Image(
                            systemName: (store.get(.favorites, as: [String].self) ?? []).contains(content.name) ? "star.fill" : "star"
                        )
                    }
                )
            }
        } else {
            ProgressView()
                .onAppear {
                    store.handle(action: .fetchPokemon)
                }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(
            store: Store(
                initialValues: [
                    .pokemonIndex: 1,
                    .favorites: []
                ],
                actionHandler: pokedexActionHandler,
                dependency: .mock
            )
        )
    }
}
